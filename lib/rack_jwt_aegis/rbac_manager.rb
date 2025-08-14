# frozen_string_literal: true

module RackJwtAegis
  # Role-Based Access Control (RBAC) manager
  #
  # Handles authorization by checking user permissions against cached RBAC data.
  # Supports both simple boolean permissions and complex permission structures.
  # Uses a two-tier caching system for performance optimization.
  #
  # @author Ken Camajalan Demanawa
  # @since 0.1.0
  #
  # @example Basic usage
  #   config = Configuration.new(jwt_secret: 'secret', rbac_enabled: true, rbac_cache_store: :memory)
  #   manager = RbacManager.new(config)
  #   manager.authorize(request, jwt_payload)
  class RbacManager
    include DebugLogger

    CACHE_TTL = 300 # 5 minutes default cache TTL

    # Initialize the RBAC manager
    #
    # @param config [Configuration] the configuration instance
    def initialize(config)
      @config = config
      setup_cache_adapters
    end

    # Authorize a request against RBAC permissions
    #
    # @param request [Rack::Request] the incoming request
    # @param payload [Hash] the JWT payload containing user information
    # @raise [AuthorizationError] if user lacks sufficient permissions
    def authorize(request, payload)
      user_id = payload[@config.payload_key(:user_id).to_s]
      raise AuthorizationError, 'User ID missing from JWT payload' if user_id.nil?

      # Build permission key
      permission_key = build_permission_key(user_id, request)

      # Check cached permission first (if middleware can write to cache)
      if @permission_cache && @config.cache_write_enabled?
        cached_permission = check_cached_permission(permission_key)
        return if cached_permission == true

        raise AuthorizationError, 'Access denied - cached permission' if cached_permission == false
      end

      # Permission not cached or cache miss - check RBAC store
      has_permission = check_rbac_permission(user_id, request)

      # Cache the result if middleware has write access
      cache_permission_result(permission_key, has_permission)

      return if has_permission

      raise AuthorizationError, 'Access denied - insufficient permissions'
    end

    private

    def setup_cache_adapters
      if @config.cache_write_enabled? && @config.cache_store
        # Shared cache mode - both RBAC and permission cache use same store
        @rbac_cache = CacheAdapter.build(@config.cache_store, @config.cache_options || {})
        @permission_cache = @rbac_cache
      else
        # Separate cache mode - different stores for RBAC and permissions
        if @config.rbac_cache_store
          @rbac_cache = CacheAdapter.build(@config.rbac_cache_store, @config.rbac_cache_options || {})
        end

        if @config.permission_cache_store
          @permission_cache = CacheAdapter.build(@config.permission_cache_store, @config.permission_cache_options || {})
        end
      end

      # Ensure we have at least RBAC cache for permission lookups
      return if @rbac_cache

      raise ConfigurationError, 'RBAC cache store not configured'
    end

    def build_permission_key(user_id, request)
      "#{user_id}:#{request.host}#{request.path}:#{request.request_method.downcase}"
    end

    def check_cached_permission(permission_key)
      return nil unless @permission_cache

      begin
        # Get the cached user permissions
        user_permissions = @permission_cache.read('user_permissions')
        return nil if user_permissions.nil? || !user_permissions.is_a?(Hash)

        # First check: If RBAC permissions were updated recently, nuke ALL cached permissions
        rbac_last_update = rbac_last_update_timestamp
        if rbac_last_update
          rbac_update_age = Time.now.to_i - rbac_last_update

          # If RBAC was updated within the TTL period, all cached permissions are invalid
          if rbac_update_age <= @config.user_permissions_ttl
            nuke_user_permissions_cache("RBAC permissions updated recently (#{rbac_update_age}s ago, within TTL)")
            return nil
          end
        end

        # Check if permission exists in this format: {"user_id:full_url:method" => timestamp}
        cached_timestamp = user_permissions[permission_key]
        return nil unless cached_timestamp.is_a?(Integer)

        permission_age = Time.now.to_i - cached_timestamp

        # Second check: TTL expiration
        if permission_age > @config.user_permissions_ttl
          # This specific permission expired due to TTL
          remove_stale_permission(permission_key,
                                  "TTL expired (#{permission_age}s > #{@config.user_permissions_ttl}s)")
          return nil
        end

        # Permission is fresh
        debug_log("Cache hit: #{permission_key} (permission age: \
                  #{permission_age}s, RBAC age: #{rbac_update_age || 'unknown'}s)".squeeze)
        true
      rescue CacheError => e
        # Log cache error but don't fail the request
        debug_log("RbacManager cache read error: #{e.message}", :warn)
        nil
      end
    end

    def check_rbac_permission(user_id, request)
      rbac_data = @rbac_cache.read('permissions')

      # Check if RBAC data exists and is valid
      if rbac_data.is_a?(Hash) && validate_rbac_cache_format(rbac_data)
        return check_rbac_format?(user_id, request, rbac_data)
      end

      # No valid RBAC data found
      false
    rescue CacheError => e
      # Cache error - fail secure (deny access)
      debug_log("RbacManager RBAC cache error: #{e.message}", :warn)
      false
    end

    def cache_permission_result(permission_key, has_permission)
      return unless @permission_cache
      return unless has_permission # Only cache positive permissions

      begin
        current_time = Time.now.to_i

        # Get existing user permissions cache or create new one
        user_permissions = @permission_cache.read('user_permissions') || {}

        # Store permission with new format: {"user_id:full_url:method" => timestamp}
        user_permissions[permission_key] = current_time

        # Write back to cache
        @permission_cache.write('user_permissions', user_permissions, expires_in: CACHE_TTL)

        debug_log("Cached permission: #{permission_key} => #{current_time}")
      rescue CacheError => e
        # Log cache error but don't fail the request
        debug_log("RbacManager permission cache write error: #{e.message}", :warn)
      end
    end

    def check_rbac_format?(user_id, request, rbac_data)
      # Extract user roles from JWT payload
      user_roles = extract_user_roles_from_request(request)
      if user_roles.nil? || user_roles.empty?
        debug_log('RbacManager: No user roles found in request context', :warn)
        return false
      end

      # Check permissions for each user role
      rbac_data['permissions'].each do |role_permissions|
        user_roles.each do |role_id|
          next unless role_permissions.key?(role_id.to_s) || role_permissions.key?(role_id.to_i)

          permissions = role_permissions[role_id.to_s] || role_permissions[role_id.to_i]
          matched_permission = find_matching_permission(permissions, request)

          next unless matched_permission

          # Cache this specific permission match for faster future lookups
          if @permission_cache && @config.cache_write_enabled?
            cache_permission_match(user_id, request, role_id, matched_permission)
          end
          return true
        end
      end

      false
    end

    # Get RBAC permissions collection last_update timestamp
    def rbac_last_update_timestamp
      return nil unless @rbac_cache

      begin
        rbac_data = @rbac_cache.read('permissions')
        if rbac_data.is_a?(Hash) && (rbac_data.key?('last_update') || rbac_data.key?(:last_update))
          return rbac_data['last_update'] || rbac_data[:last_update]
        end

        nil
      rescue CacheError => e
        debug_log("RbacManager RBAC last-update read error: #{e.message}", :warn)
        nil
      end
    end

    # Remove a specific stale permission
    def remove_stale_permission(permission_key, reason)
      return unless @permission_cache

      begin
        user_permissions = @permission_cache.read('user_permissions')
        return unless user_permissions.is_a?(Hash)

        # Remove the specific permission key
        user_permissions.delete(permission_key)

        # If no permissions remain, remove the entire cache
        if user_permissions.empty?
          @permission_cache.delete('user_permissions')
          debug_log("Removed last permission, cleared entire cache: #{reason}")
        else
          # Update the cache with the modified permissions
          @permission_cache.write('user_permissions', user_permissions, expires_in: CACHE_TTL)
          debug_log("Removed stale permission #{permission_key}: #{reason}")
        end
      rescue CacheError => e
        debug_log("RbacManager stale permission removal error: #{e.message}", :warn)
      end
    end

    # Nuke (delete) the entire user permissions cache
    def nuke_user_permissions_cache(reason)
      return unless @permission_cache

      begin
        @permission_cache.delete('user_permissions')
        debug_log("Nuked user permissions cache: #{reason}")
      rescue CacheError => e
        debug_log("RbacManager cache nuke error: #{e.message}", :warn)
      end
    end

    # Extract user roles from request context (stored by middleware)
    def extract_user_roles_from_request(request)
      # Check if roles are stored in request environment by middleware
      request.env['rack_jwt_aegis.user_roles']
    end

    # Check if any role permission matches the request
    def check_role_permissions?(permissions, request)
      return false unless permissions.is_a?(Array)

      request_path = extract_api_path_from_request(request)
      request_method = request.request_method.downcase

      permissions.each do |permission|
        return true if permission_matches?(permission, request_path, request_method)
      end

      false
    end

    # Find the first matching permission for the request (returns the permission string or nil)
    def find_matching_permission(permissions, request)
      return nil unless permissions.is_a?(Array)

      request_path = extract_api_path_from_request(request)
      request_method = request.request_method.downcase

      permissions.each do |permission|
        return permission if permission_matches?(permission, request_path, request_method)
      end

      nil
    end

    # Cache the specific permission match for faster future lookups
    # Format: {"user_id:full_url:method" => timestamp}
    def cache_permission_match(user_id, request, _role_id, _matched_permission)
      return unless @permission_cache

      begin
        current_time = Time.now.to_i

        # Build the permission key in new format
        host = request.host || 'localhost'
        full_url = "#{host}#{request.path}"
        method = request.request_method.downcase
        permission_key = "#{user_id}:#{full_url}:#{method}"

        # Get existing user permissions cache or create new one
        user_permissions = @permission_cache.read('user_permissions') || {}

        # Store permission with new format
        user_permissions[permission_key] = current_time

        # Write back to cache
        @permission_cache.write('user_permissions', user_permissions, expires_in: CACHE_TTL)

        debug_log("Cached user permission: #{permission_key} => #{current_time}")
      rescue CacheError => e
        # Log cache error but don't fail the request
        debug_log("RbacManager permission cache write error: #{e.message}", :warn)
      end
    end

    # Extract the API path portion from the full request path
    # Removes subdomain and pathname slug parts to get the resource endpoint
    def extract_api_path_from_request(request)
      path = request.path

      # Remove API prefix and pathname slug pattern if configured
      if @config.pathname_slug_pattern
        # Extract the resource path after the pathname slug
        match = path.match(@config.pathname_slug_pattern)
        if match&.captures&.any?
          # Get everything after the slug pattern
          slug_part = match[0]
          resource_path = path.sub(slug_part, '')
          return resource_path.start_with?('/') ? resource_path[1..] : resource_path
        end
      end

      # Fallback: remove common API prefixes
      path = path.sub(%r{^/api/v\d+/}, '')
      path = path.sub(%r{^/api/}, '')
      path.sub(%r{^/}, '')
    end

    # Check if a permission string matches the request
    def permission_matches?(permission, resource_path, request_method)
      return false unless permission.is_a?(String)

      # Parse permission format: "resource-endpoint:http-method"
      parts = permission.split(':')
      return false unless parts.length == 2

      permission_path, permission_method = parts

      # Check if method matches
      return false unless method_matches?(permission_method, request_method)

      # Check if path matches (handle both literal and regex patterns)
      path_matches?(permission_path, resource_path)
    end

    # Check if HTTP method matches
    def method_matches?(permission_method, request_method)
      permission_method = permission_method.downcase

      # Wildcard method matches all
      return true if permission_method == '*'

      # Exact method match
      permission_method == request_method
    end

    # Check if path matches (handles both literal strings and regex patterns)
    def path_matches?(permission_path, resource_path)
      # Handle regex pattern format: "%r{pattern}"
      if permission_path.start_with?('%r{') && permission_path.end_with?('}')
        regex_pattern = permission_path[3..-2] # Remove %r{ and }
        begin
          regex = Regexp.new(regex_pattern)
          return regex.match?(resource_path)
        rescue RegexpError => e
          debug_log("RbacManager: Invalid regex pattern '#{regex_pattern}': #{e.message}", :warn)
          return false
        end
      end

      # Exact string match
      permission_path == resource_path
    end

    # Validate RBAC cache format according to specification
    # Expected format:
    # {
    #   last_update: timestamp,
    #   permissions: [
    #     {role-id: ["{resource-endpoint}:{http-method}"]}
    #   ]
    # }
    def validate_rbac_cache_format(rbac_data)
      return false unless rbac_data.is_a?(Hash)

      # Check required fields
      return false unless rbac_data.key?('last_update') || rbac_data.key?(:last_update)
      return false unless rbac_data.key?('permissions') || rbac_data.key?(:permissions)

      # Get permissions array
      permissions = rbac_data['permissions'] || rbac_data[:permissions]
      return false unless permissions.is_a?(Array)

      # Validate each permission entry
      permissions.each do |permission_entry|
        return false unless permission_entry.is_a?(Hash)

        # Each entry should have at least one role-id key
        return false if permission_entry.empty?

        # Validate permission values are arrays of strings
        permission_entry.each_value do |role_permissions|
          return false unless role_permissions.is_a?(Array)

          # Each permission should be a string in format "endpoint:method"
          role_permissions.each do |permission|
            return false unless permission.is_a?(String)
            # Permission must include ':' (resource:method format)
            return false unless permission.include?(':')
          end
        end
      end

      true
    rescue StandardError => e
      debug_log("RbacManager: Cache format validation error: #{e.message}", :warn)
      false
    end
  end
end
