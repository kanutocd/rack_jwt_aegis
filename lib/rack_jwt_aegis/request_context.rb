# frozen_string_literal: true

module RackJwtAegis
  class RequestContext
    # Standard environment keys for JWT data
    JWT_PAYLOAD_KEY = 'rack_jwt_aegis.payload'
    USER_ID_KEY = 'rack_jwt_aegis.user_id'
    COMPANY_GROUP_ID_KEY = 'rack_jwt_aegis.company_group_id'
    COMPANY_GROUP_DOMAIN_KEY = 'rack_jwt_aegis.company_group_domain'
    COMPANY_SLUGS_KEY = 'rack_jwt_aegis.company_slugs'
    AUTHENTICATED_KEY = 'rack_jwt_aegis.authenticated'

    def initialize(config)
      @config = config
    end

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
    def self.authenticated?(env)
      !!env[AUTHENTICATED_KEY]
    end

    def self.payload(env)
      env[JWT_PAYLOAD_KEY]
    end

    def self.user_id(env)
      env[USER_ID_KEY]
    end

    def self.company_group_id(env)
      env[COMPANY_GROUP_ID_KEY]
    end

    def self.company_group_domain(env)
      env[COMPANY_GROUP_DOMAIN_KEY]
    end

    def self.company_slugs(env)
      env[COMPANY_SLUGS_KEY] || []
    end

    def self.current_user_id(request)
      user_id(request.env)
    end

    def self.current_company_group_id(request)
      company_group_id(request.env)
    end

    def self.has_company_access?(env, company_slug)
      company_slugs(env).include?(company_slug)
    end

    private

    def set_user_context(env, payload)
      user_id_key = @config.payload_key(:user_id).to_s
      user_id = payload[user_id_key]

      env[USER_ID_KEY] = user_id
    end

    def set_tenant_context(env, payload)
      # Set company group information
      if @config.validate_subdomain? || @config.payload_mapping.key?(:company_group_id)
        company_group_id_key = @config.payload_key(:company_group_id).to_s
        company_group_id = payload[company_group_id_key]
        env[COMPANY_GROUP_ID_KEY] = company_group_id
      end

      if @config.validate_subdomain?
        company_domain_key = @config.payload_key(:company_group_domain).to_s
        company_domain = payload[company_domain_key]
        env[COMPANY_GROUP_DOMAIN_KEY] = company_domain
      end

      # Set company slugs for sub-level tenant access
      return unless @config.validate_company_slug? || @config.payload_mapping.key?(:company_slugs)

      company_slugs_key = @config.payload_key(:company_slugs).to_s
      company_slugs = payload[company_slugs_key]

      # Ensure it's an array
      company_slugs = Array(company_slugs) if company_slugs
      env[COMPANY_SLUGS_KEY] = company_slugs || []
    end
  end
end
