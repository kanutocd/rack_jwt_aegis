# frozen_string_literal: true

module RackJwtAegis
  class Configuration
    # Core JWT settings
    attr_accessor :jwt_secret, :jwt_algorithm

    # Feature toggles
    attr_accessor :validate_subdomain, :validate_pathname_slug, :rbac_enabled

    # Multi-tenant settings
    attr_accessor :tenant_id_header_name, :pathname_slug_pattern, :payload_mapping

    # Path management
    attr_accessor :skip_paths

    # Cache configuration
    attr_accessor :cache_store, :cache_options, :cache_write_enabled
    attr_accessor :rbac_cache_store, :rbac_cache_options, :permission_cache_store, :permission_cache_options

    # Custom validators
    attr_accessor :custom_payload_validator

    # Response customization
    attr_accessor :unauthorized_response, :forbidden_response

    # Development settings
    attr_accessor :debug_mode

    def initialize(options = {})
      # Set defaults
      set_defaults

      # Merge user options
      options.each do |key, value|
        raise ConfigurationError, "Unknown configuration option: #{key}" unless respond_to?("#{key}=")

        public_send("#{key}=", value)
      end

      # Validate configuration
      validate!
    end

    def rbac_enabled?
      config_boolean?(rbac_enabled)
    end

    def validate_subdomain?
      config_boolean?(validate_subdomain)
    end

    def validate_pathname_slug?
      config_boolean?(validate_pathname_slug)
    end

    def debug_mode?
      config_boolean?(debug_mode)
    end

    def cache_write_enabled?
      config_boolean?(cache_write_enabled)
    end

    # Check if path should be skipped
    def skip_path?(path)
      return false if skip_paths.nil? || skip_paths.empty?

      skip_paths.any? do |skip_path|
        case skip_path
        when String
          path == skip_path
        when Regexp
          skip_path.match?(path)
        else
          false
        end
      end
    end

    # Get mapped payload key
    def payload_key(standard_key)
      payload_mapping&.fetch(standard_key, standard_key) || standard_key
    end

    private

    # Convert various falsy/truthy values to proper boolean for configuration
    def config_boolean?(value)
      if (value.is_a?(Numeric) && value.zero?) ||
         (value.is_a?(String) && ['false', '0', '', 'no'].include?(value.downcase.strip))
        return false
      end

      # Everything else is truthy
      !!value
    end

    def set_defaults
      @jwt_algorithm = 'HS256'
      @validate_subdomain = false
      @validate_pathname_slug = false
      @rbac_enabled = false
      @tenant_id_header_name = 'X-Tenant-Id'
      @pathname_slug_pattern = %r{^/api/v1/([^/]+)/}
      @skip_paths = []
      @cache_write_enabled = false
      @debug_mode = false
      @payload_mapping = {
        user_id: :user_id,
        tenant_id: :tenant_id,
        subdomain: :subdomain,
        pathname_slugs: :pathname_slugs,
      }
      @unauthorized_response = { error: 'Authentication required' }
      @forbidden_response = { error: 'Access denied' }
    end

    def validate!
      validate_jwt_settings!
      validate_cache_settings!
      validate_multi_tenant_settings!
    end

    def validate_jwt_settings!
      raise ConfigurationError, 'jwt_secret is required' if jwt_secret.nil? || jwt_secret.empty?

      valid_algorithms = ['HS256', 'HS384', 'HS512', 'RS256', 'RS384', 'RS512', 'ES256', 'ES384', 'ES512']
      return if valid_algorithms.include?(jwt_algorithm)

      raise ConfigurationError, "Unsupported JWT algorithm: #{jwt_algorithm}"
    end

    def validate_cache_settings!
      return unless rbac_enabled?

      # Validate cache store configuration
      if cache_store && !cache_write_enabled?
        # Zero trust mode - separate caches required
        if rbac_cache_store.nil?
          raise ConfigurationError, 'rbac_cache_store is required when cache_write_enabled is false'
        end

        if permission_cache_store.nil?
          @permission_cache_store = :memory # Default fallback
        end
      elsif cache_store.nil? && rbac_cache_store.nil?
        # Both cache stores are missing - at least one is required for RBAC
        raise ConfigurationError, 'cache_store or rbac_cache_store is required when RBAC is enabled'
      end

      # Set default fallback for permission_cache_store when rbac_cache_store is provided
      return unless !rbac_cache_store.nil? && permission_cache_store.nil?

      @permission_cache_store = :memory # Default fallback
    end

    def validate_multi_tenant_settings!
      if validate_pathname_slug? && pathname_slug_pattern.nil?
        raise ConfigurationError, 'pathname_slug_pattern is required when validate_pathname_slug is true'
      end

      if validate_subdomain? && !payload_mapping.key?(:subdomain)
        raise ConfigurationError, 'payload_mapping must include :subdomain when validate_subdomain is true'
      end

      return unless validate_pathname_slug? && !payload_mapping.key?(:pathname_slugs)

      raise ConfigurationError, 'payload_mapping must include :pathname_slugs when validate_pathname_slug is true'
    end
  end
end
