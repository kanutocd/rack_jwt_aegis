# frozen_string_literal: true

module RackJwtAegis
  # Configuration class for RackJwtAegis middleware
  #
  # Manages all configuration options for JWT authentication, multi-tenant validation,
  # RBAC authorization, and caching behavior.
  #
  # @author Ken Camajalan Demanawa
  # @since 0.1.0
  #
  # @example Basic configuration
  #   config = Configuration.new(jwt_secret: 'your-secret')
  #
  # @example Full configuration
  #   config = Configuration.new(
  #     jwt_secret: ENV['JWT_SECRET'],
  #     jwt_algorithm: 'HS256',
  #     validate_subdomain: true,
  #     validate_pathname_slug: true,
  #     rbac_enabled: true,
  #     skip_paths: ['/health', '/api/public/*'],
  #     debug_mode: Rails.env.development?
  #   )
  class Configuration
    # @!group Core JWT Settings

    # The secret key used for JWT signature verification
    # @return [String] the JWT secret key
    # @note This is required and must not be empty
    attr_accessor :jwt_secret

    # The JWT algorithm to use for token verification
    # @return [String] the JWT algorithm (default: 'HS256')
    # @note Supported algorithms: HS256, HS384, HS512, RS256, RS384, RS512, ES256, ES384, ES512
    attr_accessor :jwt_algorithm

    # @!endgroup

    # @!group Feature Toggles

    # Whether to validate subdomain-based multi-tenancy
    # @return [Boolean] true if subdomain validation is enabled
    attr_accessor :validate_subdomain

    # Whether to validate pathname slug-based multi-tenancy
    # @return [Boolean] true if pathname slug validation is enabled
    attr_accessor :validate_pathname_slug

    # Whether to validate tenant id from request header against the tenant id from JWT payload
    # @return [Boolean] true if tenant id validation is enabled
    attr_accessor :validate_tenant_id

    # Whether RBAC (Role-Based Access Control) is enabled
    # @return [Boolean] true if RBAC is enabled
    attr_accessor :rbac_enabled

    # @!endgroup

    # @!group Multi-tenant Settings

    # The HTTP header name containing the tenant ID
    # @return [String] the tenant ID header name (default: 'X-Tenant-Id')
    attr_accessor :tenant_id_header_name

    # The regular expression pattern to extract pathname slugs
    # @return [Regexp] the pathname slug pattern (default: /^\/api\/v1\/([^\/]+)\//)
    attr_accessor :pathname_slug_pattern

    # Mapping of standard payload keys to custom JWT claim names
    # @return [Hash] the payload mapping configuration
    # @example
    #   { user_id: :sub, tenant_id: :company_id, subdomain: :domain }
    attr_accessor :payload_mapping

    # @!endgroup

    # @!group Path Management

    # Array of paths that should skip JWT authentication
    # @return [Array<String, Regexp>] paths to skip authentication for
    # @example
    #   ['/health', '/api/public', /^\/assets/]
    attr_accessor :skip_paths

    # @!endgroup

    # @!group Cache Configuration
    # The RBAC cache store adapter type (separate from main cache)
    # @return [Symbol] the RBAC cache store type
    attr_accessor :rbac_cache_store

    # Options for the RBAC cache store
    # @return [Hash] RBAC cache configuration options
    attr_accessor :rbac_cache_store_options

    # The permission cache store adapter type
    # @return [Symbol] the permission cache store type
    attr_accessor :permissions_cache_store

    # Options for the permission cache store
    # @return [Hash] permission cache configuration options
    attr_accessor :permissions_cache_store_options

    # Time-to-live for user permissions cache in seconds
    # @return [Integer] TTL in seconds (default: 1800 - 30 minutes)
    attr_accessor :cached_permissions_ttl

    # @!endgroup

    # @!group Custom Validators

    # Custom payload validation proc
    # @return [Proc] a callable that receives (payload, request) and returns boolean
    # @example
    #   ->(payload, request) { payload['role'] == 'admin' }
    attr_accessor :custom_payload_validator

    # @!endgroup

    # @!group Response Customization

    # Custom response for unauthorized requests (401)
    # @return [Hash] the unauthorized response body
    # @example
    #   { error: 'Authentication required', code: 'AUTH_001' }
    attr_accessor :unauthorized_response

    # Custom response for forbidden requests (403)
    # @return [Hash] the forbidden response body
    # @example
    #   { error: 'Access denied', code: 'AUTH_002' }
    attr_accessor :forbidden_response

    # @!endgroup

    # @!group Development Settings

    # Whether debug mode is enabled for additional logging
    # @return [Boolean] true if debug mode is enabled
    attr_accessor :debug_mode

    # @!endgroup

    # Initialize a new Configuration instance
    #
    # @param options [Hash] configuration options
    # @option options [String] :jwt_secret (required) JWT secret key for signature verification
    # @option options [String] :jwt_algorithm ('HS256') JWT algorithm to use
    # @option options [Boolean] :validate_subdomain (false) enable subdomain validation
    # @option options [Boolean] :validate_pathname_slug (false) enable pathname slug validation
    # @option options [Boolean] :rbac_enabled (false) enable RBAC authorization
    # @option options [String] :tenant_id_header_name ('X-Tenant-Id') tenant ID header name
    # @option options [Regexp] :pathname_slug_pattern default pattern for pathname slugs
    # @option options [Hash] :payload_mapping mapping of JWT claim names
    # @option options [Array<String, Regexp>] :skip_paths ([]) paths to skip authentication
    # @option options [Symbol] :rbac_cache_store cache adapter type
    # @option options [Hash] :rbac_cache_store_options cache configuration options
    # @option options [Symbol] :permissions_cache_store cache adapter type
    # @option options [Hash] :permissions_cache_store_options cache configuration options
    # @option options [Integer] :cached_permissions_ttl (1800) user permissions cache TTL in seconds
    # @option options [Boolean] :debug_mode (false) enable debug logging
    # @raise [ConfigurationError] if jwt_secret is missing or configuration is invalid
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

    # Check if RBAC is enabled
    # @return [Boolean] true if RBAC is enabled
    def rbac_enabled?
      config_boolean?(rbac_enabled)
    end

    # Check if subdomain validation is enabled
    # @return [Boolean] true if subdomain validation is enabled
    def validate_subdomain?
      config_boolean?(validate_subdomain)
    end

    # Check if pathname slug validation is enabled
    # @return [Boolean] true if pathname slug validation is enabled
    def validate_pathname_slug?
      config_boolean?(validate_pathname_slug)
    end

    # Check if tenant id validation is enabled
    # @return [Boolean] true if tenant id validation is enabled
    def validate_tenant_id?
      config_boolean?(validate_tenant_id)
    end

    # Check if debug mode is enabled
    # @return [Boolean] true if debug mode is enabled
    def debug_mode?
      config_boolean?(debug_mode)
    end

    # Check if the given path should skip JWT authentication
    # @param path [String] the request path to check
    # @return [Boolean] true if the path should be skipped
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

    # Get the mapped payload key for a standard key
    # @param standard_key [Symbol] the standard key to map
    # @return [Symbol] the mapped key from payload_mapping, or the original key if no mapping exists
    # @example
    #   config.payload_key(:user_id) #=> :sub (if mapped)
    #   config.payload_key(:user_id) #=> :user_id (if not mapped)
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
      @validate_tenant_id = false
      @tenant_id_header_name = 'X-Tenant-Id'
      @pathname_slug_pattern = %r{^/api/v1/([^/]+)/}
      @skip_paths = []
      @payload_mapping = {
        user_id: :user_id,
        tenant_id: :tenant_id,
        subdomain: :subdomain,
        pathname_slugs: :pathname_slugs,
        role_ids: :role_ids,
      }
      @unauthorized_response = { error: 'Authentication required' }
      @forbidden_response = { error: 'Access denied' }
      @rbac_enabled = false
      @cached_permissions_ttl = 1800 # 30 minutes default
      @rbac_cache_store = if Object.const_defined?(:Rails) && Rails.const_defined?(:Application)
                            @debug_mode = Rails.env.development?
                            Rails.application.config.cache_store
                          else
                            @debug_mode = false
                            :memory
                          end
      @permissions_cache_store = @rbac_cache_store
      @rbac_cache_store_options = {}
      @permissions_cache_store_options = {}
    end

    def validate!
      validate_jwt_settings!
      validate_payload_mapping!
      validate_cache_settings!
      validate_multi_tenant_settings!
    end

    def validate_jwt_settings!
      raise ConfigurationError, 'jwt_secret is required' if jwt_secret.to_s.strip.empty?

      valid_algorithms = ['HS256', 'HS384', 'HS512', 'RS256', 'RS384', 'RS512', 'ES256', 'ES384', 'ES512']
      return if valid_algorithms.include?(jwt_algorithm)

      raise ConfigurationError, "Unsupported JWT algorithm: #{jwt_algorithm}"
    end

    def validate_payload_mapping!
      # Allow nil payload_mapping (will use defaults)
      return if payload_mapping.nil?

      raise ConfigurationError, 'payload_mapping must be a Hash' unless payload_mapping.is_a?(Hash)

      # Validate all values are symbols
      invalid_values = payload_mapping.reject { |_key, value| value.is_a?(Symbol) }
      return if invalid_values.empty?

      raise ConfigurationError, "payload_mapping values must be symbols, invalid: #{invalid_values.inspect}"

      # NOTE: We don't validate required keys because users may provide
      # partial mappings that are intended to override defaults. The payload_key method
      # handles missing keys by returning the standard key as fallback.
      # This includes RBAC keys - if :role_ids is not mapped, it falls back to 'role_ids'.
    end

    def validate_cache_settings!
      return unless rbac_enabled? && (rbac_cache_store.nil? || permissions_cache_store.nil?)

      raise ConfigurationError,
            'rbac_cache_store and permissions_cache_store are required when RBAC is enabled'
    end

    def validate_multi_tenant_settings!
      if validate_subdomain? && !payload_mapping.key?(:subdomain)
        raise ConfigurationError, 'payload_mapping must include :subdomain when validate_subdomain is true'
      end

      if validate_tenant_id?
        error_msg = []
        error_msg << 'payload_mapping must include :tenant_id' unless payload_mapping.key?(:tenant_id)
        error_msg << 'tenant_id_header_name is required' if tenant_id_header_name.to_s.strip.empty?
        raise ConfigurationError, "#{error_msg.join(' and ')} when validate_tenant_id is true" if error_msg.any?
      end

      return unless validate_pathname_slug?

      error_msg = []
      error_msg << 'payload_mapping must include :pathname_slugs' unless payload_mapping.key?(:pathname_slugs)
      error_msg << 'pathname_slug_pattern is required' if pathname_slug_pattern.to_s.empty?
      raise ConfigurationError, "#{error_msg.join(' and ')} when validate_pathname_slug is true" if error_msg.any?
    end
  end
end
