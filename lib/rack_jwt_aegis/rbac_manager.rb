# frozen_string_literal: true

module RackJwtAegis
  # Role-Based Access Control (RBAC) manager
  #
  # Handles authorization by checking user permissions against cached RBAC data.
  # Supports both simple boolean permissions and complex permission structures.
  # Uses a two-tier caching system for performance optimization.
  #
  # @author Ken Cooke
  # @since 1.0.0
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
        # Get cached permission entry
        cached_entry = @permission_cache.read(permission_key)
        return nil if cached_entry.nil?

        # Check if cached entry is still valid based on last-update timestamp
        if cached_entry.is_a?(Hash) && cached_entry['timestamp'] && cached_entry['permission']
          last_update_time = last_update_timestamp

          return cached_entry['permission'] if last_update_time && cached_entry['timestamp'] >= last_update_time

          # Cached entry is stale, remove it
          @permission_cache.delete(permission_key)
          return nil

        end

        # Invalid cached entry format
        @permission_cache.delete(permission_key)
        nil
      rescue CacheError => e
        # Log cache error but don't fail the request
        warn "RbacManager cache read error: #{e.message}" if @config.debug_mode?
        nil
      end
    end

    def check_rbac_permission(user_id, request)
      # Build RBAC lookup key
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

    def last_update_timestamp
      @rbac_cache.read(LAST_UPDATE_KEY)
    rescue CacheError => e
      warn "RbacManager last-update read error: #{e.message}" if @config.debug_mode?
      nil
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
  end
end
