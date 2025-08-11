# frozen_string_literal: true

module RackJwtAegis
  # Request context manager for storing JWT authentication data in Rack env
  #
  # Stores authenticated user and tenant information in the Rack environment
  # hash for easy access by downstream application code. Provides both
  # instance methods for setting context and class methods for reading.
  #
  # @author Ken Cooke
  # @since 1.0.0
  #
  # @example Setting context (done by middleware)
  #   context = RequestContext.new(config)
  #   context.set_context(env, jwt_payload)
  #
  # @example Reading context in application
  #   user_id = RequestContext.user_id(request.env)
  #   tenant_id = RequestContext.tenant_id(request.env)
  #   authenticated = RequestContext.authenticated?(request.env)
  class RequestContext
    # Standard environment keys for JWT data
    JWT_PAYLOAD_KEY = 'rack_jwt_aegis.payload'
    USER_ID_KEY = 'rack_jwt_aegis.user_id'
    TENANT_ID_KEY = 'rack_jwt_aegis.tenant_id'
    SUBDOMAIN_KEY = 'rack_jwt_aegis.subdomain'
    PATHNAME_SLUGS_KEY = 'rack_jwt_aegis.pathname_slugs'
    AUTHENTICATED_KEY = 'rack_jwt_aegis.authenticated'

    # Initialize the request context manager
    #
    # @param config [Configuration] the configuration instance
    def initialize(config)
      @config = config
    end

    # Set JWT authentication context in the Rack environment
    #
    # @param env [Hash] the Rack environment hash
    # @param payload [Hash] the validated JWT payload
    def set_context(env, payload)
      # Set the full payload
      env[JWT_PAYLOAD_KEY] = payload

      # Set authentication flag
      env[AUTHENTICATED_KEY] = true

      # Extract and set commonly used values for easy access
      set_user_context(env, payload)
      set_tenant_context(env, payload)
    end

    # Class methods for easy access from application code

    # Check if the request is authenticated
    #
    # @param env [Hash] the Rack environment hash
    # @return [Boolean] true if request is authenticated
    def self.authenticated?(env)
      !!env[AUTHENTICATED_KEY]
    end

    # Get the full JWT payload from the request
    #
    # @param env [Hash] the Rack environment hash
    # @return [Hash, nil] the JWT payload or nil if not authenticated
    def self.payload(env)
      env[JWT_PAYLOAD_KEY]
    end

    # Get the authenticated user ID
    #
    # @param env [Hash] the Rack environment hash
    # @return [String, Integer, nil] the user ID or nil if not available
    def self.user_id(env)
      env[USER_ID_KEY]
    end

    # Get the tenant ID
    #
    # @param env [Hash] the Rack environment hash
    # @return [String, Integer, nil] the tenant ID or nil if not available
    def self.tenant_id(env)
      env[TENANT_ID_KEY]
    end

    def self.subdomain(env)
      env[SUBDOMAIN_KEY]
    end

    def self.pathname_slugs(env)
      env[PATHNAME_SLUGS_KEY] || []
    end

    def self.current_user_id(request)
      user_id(request.env)
    end

    def self.current_tenant_id(request)
      tenant_id(request.env)
    end

    def self.has_company_access?(env, company_slug)
      pathname_slugs(env).include?(company_slug)
    end

    private

    def set_user_context(env, payload)
      user_id_key = @config.payload_key(:user_id).to_s
      user_id = payload[user_id_key]

      env[USER_ID_KEY] = user_id
    end

    def set_tenant_context(env, payload)
      # Set company group information
      if @config.validate_subdomain? || @config.payload_mapping.key?(:tenant_id)
        tenant_id_key = @config.payload_key(:tenant_id).to_s
        tenant_id = payload[tenant_id_key]
        env[TENANT_ID_KEY] = tenant_id
      end

      if @config.validate_subdomain?
        company_domain_key = @config.payload_key(:subdomain).to_s
        company_domain = payload[company_domain_key]
        env[SUBDOMAIN_KEY] = company_domain
      end

      # Set company slugs for sub-level tenant access
      return unless @config.validate_pathname_slug? || @config.payload_mapping.key?(:pathname_slugs)

      pathname_slugs_key = @config.payload_key(:pathname_slugs).to_s
      pathname_slugs = payload[pathname_slugs_key]

      # Ensure it's an array
      pathname_slugs = Array(pathname_slugs) if pathname_slugs
      env[PATHNAME_SLUGS_KEY] = pathname_slugs || []
    end
  end
end
