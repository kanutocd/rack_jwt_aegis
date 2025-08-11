# frozen_string_literal: true

require 'jwt'

module RackJwtAegis
  # JWT token validation and payload verification
  #
  # Handles JWT token decoding, signature verification, and payload validation
  # including claims verification and type checking based on configuration.
  #
  # @author Ken Cooke
  # @since 1.0.0
  #
  # @example Basic usage
  #   config = Configuration.new(jwt_secret: 'your-secret')
  #   validator = JwtValidator.new(config)
  #   payload = validator.validate(jwt_token)
  #
  # @example With multi-tenant validation
  #   config = Configuration.new(
  #     jwt_secret: 'your-secret',
  #     validate_subdomain: true,
  #     validate_pathname_slug: true
  #   )
  #   validator = JwtValidator.new(config)
  #   payload = validator.validate(jwt_token) # Will validate tenant claims
  class JwtValidator
    # Initialize the JWT validator
    #
    # @param config [Configuration] the configuration instance
    def initialize(config)
      @config = config
    end

    # Validate and decode a JWT token
    #
    # @param token [String] the JWT token to validate
    # @return [Hash] the decoded JWT payload
    # @raise [AuthenticationError] if token is invalid, expired, or malformed
    # @raise [AuthenticationError] if required claims are missing or invalid
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

    # Validate the structure and content of the JWT payload
    #
    # @param payload [Object] the decoded payload from JWT
    # @raise [AuthenticationError] if payload structure is invalid
    def validate_payload_structure(payload)
      # Ensure payload is a hash
      raise AuthenticationError, 'Invalid JWT payload structure' unless payload.is_a?(Hash)

      # Validate required claims based on enabled features
      validate_required_claims(payload)

      # Validate claim types
      validate_claim_types(payload)
    end

    # Validate that all required claims are present in the payload
    #
    # @param payload [Hash] the JWT payload to validate
    # @raise [AuthenticationError] if required claims are missing
    def validate_required_claims(payload)
      required_claims = []

      # Always require user identification
      required_claims << @config.payload_key(:user_id)

      # Multi-tenant validation requirements
      if @config.validate_subdomain?
        required_claims << @config.payload_key(:tenant_id)
        required_claims << @config.payload_key(:subdomain)
      end

      required_claims << @config.payload_key(:pathname_slugs) if @config.validate_pathname_slug?

      missing_claims = required_claims.select { |claim| payload[claim.to_s].nil? }

      return if missing_claims.empty?

      raise AuthenticationError, "JWT payload missing required claims: #{missing_claims.join(', ')}"
    end

    # Validate the data types of specific claims in the payload
    #
    # @param payload [Hash] the JWT payload to validate
    # @raise [AuthenticationError] if claim types are invalid
    def validate_claim_types(payload)
      user_id_key = @config.payload_key(:user_id).to_s

      # User ID should be numeric or string
      if payload[user_id_key] && !payload[user_id_key].is_a?(Numeric) && !payload[user_id_key].is_a?(String)
        raise AuthenticationError, 'Invalid user_id format in JWT payload'
      end

      # Company group ID should be numeric or string (if present)
      if @config.validate_subdomain?
        tenant_id_key = @config.payload_key(:tenant_id).to_s
        if payload[tenant_id_key] && !payload[tenant_id_key].is_a?(Numeric) && !payload[tenant_id_key].is_a?(String)
          raise AuthenticationError, 'Invalid tenant_id format in JWT payload'
        end
      end

      # Company group domain should be string (if present)
      if @config.validate_subdomain?
        company_domain_key = @config.payload_key(:subdomain).to_s
        if payload[company_domain_key] && !payload[company_domain_key].is_a?(String)
          raise AuthenticationError, 'Invalid subdomain format in JWT payload'
        end
      end

      # Company slugs should be array (if present)
      return unless @config.validate_pathname_slug?

      pathname_slugs_key = @config.payload_key(:pathname_slugs).to_s
      return unless payload[pathname_slugs_key] && !payload[pathname_slugs_key].is_a?(Array)

      raise AuthenticationError, 'Invalid pathname_slugs format in JWT payload - must be array'
    end
  end
end
