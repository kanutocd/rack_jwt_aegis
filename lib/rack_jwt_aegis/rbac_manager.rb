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
    CACHE_TTL = 300 # 5 minutes default cache TTL
    LAST_UPDATE_KEY = 'last-update'

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
      cache_permission_result(permission_key, has_permission) if @permission_cache && @config.cache_write_enabled?

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
      "#{user_id}:#{request.host}:#{request.path}:#{request.request_method}"
    end

    def check_cached_permission(permission_key)
      return nil unless @permission_cache

      begin
        # Get the user permissions cache
        user_permissions = @permission_cache.read('user_permissions')
        return nil if user_permissions.nil? || !user_permissions.is_a?(Hash)

        # First check: If RBAC permissions were updated recently, nuke ALL cached permissions
        rbac_last_update = get_rbac_last_update_timestamp
        if rbac_last_update
          current_time = Time.now.to_i
          rbac_update_age = current_time - rbac_last_update

          # If RBAC was updated within the TTL period, all cached permissions are invalid
          if rbac_update_age <= @config.user_permissions_ttl
            nuke_user_permissions_cache("RBAC permissions updated recently (#{rbac_update_age}s ago, within TTL)")
            return nil
          end
        end

        # Extract user_id, host, path, and method from permission_key
        # Format: "user_id:host:path:method"
        parts = permission_key.split(':', 4)
        return nil unless parts.length == 4

        user_id, host, path, method = parts
        full_url = "#{host}#{path}"

        # Check if user has cached permissions
        user_cache = user_permissions[user_id]
        return nil unless user_cache.is_a?(Hash)

        # Get permission entry for this specific URL
        url_permission = user_cache[full_url]
        return nil unless url_permission.is_a?(Array) && url_permission.length.positive?

        # Extract methods and timestamp from permission entry
        # Format: ["method1", "method2", timestamp]
        timestamp = url_permission.last
        return nil unless timestamp.is_a?(Integer)

        allowed_methods = url_permission[0..-2] # All elements except the last (timestamp)

        # Check if the specific method is allowed
        return nil unless allowed_methods.include?(method.downcase)

        current_time = Time.now.to_i
        permission_age = current_time - timestamp

        # Second check: TTL expiration (only for individual permission cleanup)
        if permission_age > @config.user_permissions_ttl
          # This specific permission expired due to TTL
          remove_stale_permission(user_id, full_url,
                                  "TTL expired (#{permission_age}s > #{@config.user_permissions_ttl}s)")
          return nil
        end

        # Permission is fresh and method is allowed
        if @config.debug_mode?
          debug_log("Cache hit: user #{user_id} has #{method.upcase} access to #{full_url} (permission age: #{permission_age}s, RBAC age: #{rbac_update_age || 'unknown'}s)")
        end
        true
      rescue CacheError => e
        # Log cache error but don't fail the request
        warn "RbacManager cache read error: #{e.message}" if @config.debug_mode?
        nil
      end
    end

    def check_rbac_permission(user_id, request)
      # First try the new RBAC permissions collection format
      rbac_data = @rbac_cache.read('permissions')

      # If new format exists and is valid, use it
      if rbac_data.is_a?(Hash) && validate_rbac_cache_format(rbac_data)
        debug_log('Using new RBAC permissions format') if @config.debug_mode?
        return check_new_rbac_format(user_id, request, rbac_data)
      end

      # Fallback to legacy format for backward compatibility
      debug_log('Falling back to legacy RBAC format') if @config.debug_mode?
      check_legacy_rbac_format(user_id, request)
    rescue CacheError => e
      # Cache error - fail secure (deny access)
      warn "RbacManager RBAC cache error: #{e.message}" if @config.debug_mode?
      false
    end

    def cache_permission_result(permission_key, has_permission)
      return unless @permission_cache

      begin
        current_time = Time.now.to_i
        cache_entry = {
          'permission' => has_permission,
          'timestamp' => current_time,
        }

        @permission_cache.write(permission_key, cache_entry, expires_in: CACHE_TTL)
      rescue CacheError => e
        # Log cache error but don't fail the request
        warn "RbacManager permission cache write error: #{e.message}" if @config.debug_mode?
      end
    end

    def check_new_rbac_format(user_id, request, rbac_data)
      # Extract user roles from JWT payload
      user_roles = extract_user_roles_from_request(request)
      if user_roles.nil? || user_roles.empty?
        warn 'RbacManager: No user roles found in request context' if @config.debug_mode?
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
            cache_specific_permission_match(user_id, request, role_id, matched_permission)
          end
          return true
        end
      end

      false
    end

    def check_legacy_rbac_format(user_id, request)
      # Build RBAC lookup key for legacy format
      rbac_key = build_rbac_key(user_id, request.host, request.path, request.request_method)

      # Check RBAC cache store for permission
      permission_data = @rbac_cache.read(rbac_key)

      if permission_data.nil?
        # No explicit permission found - default to deny
        false
      else
        # Permission data found - check if it grants access
        case permission_data
        when true, 'true', 1, '1'
          true
        when false, 'false', 0, '0'
          false
        else
          # Complex permission data - delegate to custom logic if available
          evaluate_complex_permission?(permission_data, user_id, request)
        end
      end
    end

    def last_update_timestamp
      # Try to get from RBAC permissions cache first (new format)
      rbac_data = @rbac_cache.read('permissions')
      if rbac_data.is_a?(Hash) && (rbac_data['last_update'] || rbac_data[:last_update])
        return rbac_data['last_update'] || rbac_data[:last_update]
      end

      # Fallback to legacy format
      @rbac_cache.read(LAST_UPDATE_KEY)
    rescue CacheError => e
      warn "RbacManager last-update read error: #{e.message}" if @config.debug_mode?
      nil
    end

    # Get RBAC permissions collection last_update timestamp
    def get_rbac_last_update_timestamp
      return nil unless @rbac_cache

      begin
        # Try new RBAC permissions format first
        rbac_data = @rbac_cache.read('permissions')
        if rbac_data.is_a?(Hash) && (rbac_data['last_update'] || rbac_data[:last_update])
          return rbac_data['last_update'] || rbac_data[:last_update]
        end

        # Fallback to legacy format
        @rbac_cache.read(LAST_UPDATE_KEY)
      rescue CacheError => e
        warn "RbacManager RBAC last-update read error: #{e.message}" if @config.debug_mode?
        nil
      end
    end

    # Remove a specific stale permission for a user/URL combination
    def remove_stale_permission(user_id, full_url, reason)
      return unless @permission_cache

      begin
        user_permissions = @permission_cache.read('user_permissions')
        return unless user_permissions.is_a?(Hash)
        return unless user_permissions[user_id].is_a?(Hash)

        # Remove the specific URL permission
        user_permissions[user_id].delete(full_url)

        # If user has no more cached permissions, remove the user entry
        user_permissions.delete(user_id) if user_permissions[user_id].empty?

        # If no users have cached permissions, remove the entire cache
        if user_permissions.empty?
          @permission_cache.delete('user_permissions')
          debug_log("Removed last permission, cleared entire cache: #{reason}") if @config.debug_mode?
        else
          # Update the cache with the modified permissions
          @permission_cache.write('user_permissions', user_permissions, expires_in: CACHE_TTL)
          debug_log("Removed stale permission for user #{user_id} URL #{full_url}: #{reason}") if @config.debug_mode?
        end
      rescue CacheError => e
        warn "RbacManager stale permission removal error: #{e.message}" if @config.debug_mode?
      end
    end

    # Nuke (delete) the entire user permissions cache
    def nuke_user_permissions_cache(reason)
      return unless @permission_cache

      begin
        @permission_cache.delete('user_permissions')
        debug_log("Nuked user permissions cache: #{reason}") if @config.debug_mode?
      rescue CacheError => e
        warn "RbacManager cache nuke error: #{e.message}" if @config.debug_mode?
      end
    end

    def build_rbac_key(user_id, host, path, method)
      # Standard RBAC key format as defined in architecture
      "#{user_id}:#{host}:#{path}:#{method}"
    end

    def evaluate_complex_permission?(permission_data, user_id, request)
      # Handle complex permission data structures
      case permission_data
      when Hash
        # Permission data is a hash - could contain role-based rules
        evaluate_hash_permission?(permission_data, user_id, request)
      when Array
        # Permission data is an array - could be list of allowed actions
        evaluate_array_permission?(permission_data, request.request_method)
      else
        # Unknown format - default to deny
        false
      end
    end

    def evaluate_hash_permission?(permission_hash, _user_id, request)
      # Example: {"allowed_methods": ["GET", "POST"], "roles": ["admin"]}

      # Check allowed methods
      if permission_hash['allowed_methods']
        allowed_methods = Array(permission_hash['allowed_methods'])
        return allowed_methods.include?(request.request_method)
      end

      # Check roles (would need role information from JWT payload)
      if permission_hash['roles']
        # This would require additional JWT payload inspection
        # For now, default to allowing if roles are specified
        return true
      end

      # Check boolean permission field
      return !!permission_hash['allowed'] if permission_hash.key?('allowed')

      # Default deny for unknown hash structure
      false
    end

    def evaluate_array_permission?(permission_array, request_method)
      # Array of allowed HTTP methods
      permission_array.include?(request_method)
    end

    # Extract user roles from request context (stored by middleware)
    def extract_user_roles_from_request(request)
      # Check if roles are stored in request environment by middleware
      request.env['rack_jwt_aegis.user_roles']
    end

    # Check if any role permission matches the request
    def check_role_permissions(permissions, request)
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
    # Format: { user_id: { "request-full-url": ["http-method1", "http-method2", timestamp] } }
    def cache_specific_permission_match(user_id, request, _role_id, _matched_permission)
      return unless @permission_cache

      begin
        current_time = Time.now.to_i

        # Build the full URL key
        host = request.host || 'localhost'
        full_url = "#{host}#{request.path}"
        method = request.request_method.downcase

        # Get existing user permissions cache or create new one
        user_permissions = @permission_cache.read('user_permissions') || {}
        user_permissions[user_id.to_s] ||= {}

        # Get existing permission entry for this URL
        url_permissions = user_permissions[user_id.to_s][full_url]

        if url_permissions.is_a?(Array) && url_permissions.length.positive?
          # Extract existing methods and timestamp
          url_permissions.last.is_a?(Integer) ? url_permissions.pop : current_time
          existing_methods = url_permissions

          # Add the new method if not already present
          existing_methods << method unless existing_methods.include?(method)

          # Update with new timestamp and methods
          user_permissions[user_id.to_s][full_url] = existing_methods + [current_time]
        else
          # First permission for this URL
          user_permissions[user_id.to_s][full_url] = [method, current_time]
        end

        # Write back to cache
        @permission_cache.write('user_permissions', user_permissions, expires_in: CACHE_TTL)

        if @config.debug_mode?
          debug_log("Cached user permission: user_id=#{user_id}, url=#{full_url}, method=#{method}, timestamp=#{current_time}")
        end
      rescue CacheError => e
        # Log cache error but don't fail the request
        warn "RbacManager permission cache write error: #{e.message}" if @config.debug_mode?
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
          warn "RbacManager: Invalid regex pattern '#{regex_pattern}': #{e.message}" if @config.debug_mode?
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
            return false unless permission.include?(':')
          end
        end
      end

      true
    rescue StandardError => e
      warn "RbacManager: Cache format validation error: #{e.message}" if @config.debug_mode?
      false
    end

    # Log debug message if debug mode is enabled
    def debug_log(message)
      return unless @config.debug_mode?

      timestamp = Time.now.strftime('%Y-%m-%d %H:%M:%S.%L')
      puts "[#{timestamp}] RbacManager: #{message}"
    end
  end
end
