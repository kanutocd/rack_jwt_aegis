# frozen_string_literal: true

require 'jwt'

module RackJwtAegis
  class JwtValidator
    def initialize(config)
      @config = config
    end

    def validate(token)
      # Decode JWT with verification
      payload, _header = JWT.decode(
        token,
        @config.jwt_secret,
        true, # verify signature
        {
          algorithm: @config.jwt_algorithm,
          verify_expiration: true,
          verify_not_before: true,
          verify_iat: true,
          verify_aud: false, # Not validating audience by default
          verify_iss: false, # Not validating issuer by default
          verify_sub: false, # Not validating subject by default
        },
      )

      # Validate payload structure
      validate_payload_structure(payload)

      payload
    rescue JWT::ExpiredSignature
      raise AuthenticationError, 'JWT token has expired'
    rescue JWT::ImmatureSignature
      raise AuthenticationError, 'JWT token not yet valid'
    rescue JWT::InvalidIatError
      raise AuthenticationError, 'JWT token issued in the future'
    rescue JWT::DecodeError => e
      raise AuthenticationError, "Invalid JWT token: #{e.message}"
    rescue JWT::VerificationError
      raise AuthenticationError, 'JWT signature verification failed'
    rescue StandardError => e
      raise AuthenticationError, "JWT validation error: #{e.message}"
    end

    private

    def validate_payload_structure(payload)
      # Ensure payload is a hash
      raise AuthenticationError, 'Invalid JWT payload structure' unless payload.is_a?(Hash)

      # Validate required claims based on enabled features
      validate_required_claims(payload)

      # Validate claim types
      validate_claim_types(payload)
    end

    def validate_required_claims(payload)
      required_claims = []

      # Always require user identification
      required_claims << @config.payload_key(:user_id)

      # Multi-tenant validation requirements
      if @config.validate_subdomain?
        required_claims << @config.payload_key(:company_group_id)
        required_claims << @config.payload_key(:company_group_domain)
      end

      required_claims << @config.payload_key(:company_slugs) if @config.validate_company_slug?

      missing_claims = required_claims.select { |claim| payload[claim.to_s].nil? }

      return if missing_claims.empty?

      raise AuthenticationError, "JWT payload missing required claims: #{missing_claims.join(', ')}"
    end

    def validate_claim_types(payload)
      user_id_key = @config.payload_key(:user_id).to_s

      # User ID should be numeric or string
      if payload[user_id_key] && !payload[user_id_key].is_a?(Numeric) && !payload[user_id_key].is_a?(String)
        raise AuthenticationError, 'Invalid user_id format in JWT payload'
      end

      # Company group ID should be numeric or string (if present)
      if @config.validate_subdomain?
        company_group_id_key = @config.payload_key(:company_group_id).to_s
        if payload[company_group_id_key] && !payload[company_group_id_key].is_a?(Numeric) && !payload[company_group_id_key].is_a?(String)
          raise AuthenticationError, 'Invalid company_group_id format in JWT payload'
        end
      end

      # Company group domain should be string (if present)
      if @config.validate_subdomain?
        company_domain_key = @config.payload_key(:company_group_domain).to_s
        if payload[company_domain_key] && !payload[company_domain_key].is_a?(String)
          raise AuthenticationError, 'Invalid company_group_domain format in JWT payload'
        end
      end

      # Company slugs should be array (if present)
      return unless @config.validate_company_slug?

      company_slugs_key = @config.payload_key(:company_slugs).to_s
      return unless payload[company_slugs_key] && !payload[company_slugs_key].is_a?(Array)

      raise AuthenticationError, 'Invalid company_slugs format in JWT payload - must be array'
    end
  end
end
