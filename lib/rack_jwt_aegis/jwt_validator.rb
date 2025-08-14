# frozen_string_literal: true

require 'jwt'

module RackJwtAegis
  # JWT token validation and payload verification
  #
  # Handles JWT token decoding, signature verification, and payload validation
  # including claims verification and type checking based on configuration.
  #
  # @author Ken Camajalan Demanawa
  # @since 0.1.0
  #
  # @example Basic usage
  #   config = Configuration.new(jwt_secret: 'your-secret')
  #   validator = JwtValidator.new(config)
  #   payload = validator.validate(jwt_token)
  #
  # @example With multi-tenant validation
  #   config = Configuration.new(
  #     jwt_secret: 'your-secret',
  #     validate_tenant_id: true,
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
    rescue JWT::VerificationError
      raise AuthenticationError, 'JWT signature verification failed'
    rescue JWT::DecodeError => e
      raise AuthenticationError, "Invalid JWT token: #{e.message}"
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
      # Always require user identification
      required_claims = [@config.payload_key(:user_id)]
      required_claims << @config.payload_key(:subdomain) if @config.validate_subdomain?
      required_claims << @config.payload_key(:tenant_id) if @config.validate_tenant_id?
      required_claims << @config.payload_key(:pathname_slugs) if @config.validate_pathname_slug?
      required_claims << @config.payload_key(:role_ids) if @config.rbac_enabled?

      missing_claims = required_claims.select { |claim| payload[claim.to_s].to_s.empty? }
      return if missing_claims.empty?

      raise AuthenticationError, "JWT payload missing required claims: #{missing_claims.join(', ')}"
    end

    # Validate the data types of specific claims in the payload
    #
    # @param payload [Hash] the JWT payload to validate
    # @raise [AuthenticationError] if claim types are invalid
    def validate_claim_types(payload)
      user_id = payload[@config.payload_key(:user_id).to_s]
      # User ID should be numeric or string
      if user_id.to_s.empty? || (!user_id.is_a?(Numeric) && !user_id.is_a?(String))
        raise AuthenticationError, 'Invalid user_id format in JWT payload'
      end

      # Tenant ID should be numeric or string (if present)
      if @config.validate_tenant_id?
        tenant_id = payload[@config.payload_key(:tenant_id).to_s]
        if tenant_id.to_s.empty? || (!tenant_id.is_a?(Numeric) && !tenant_id.is_a?(String))
          raise AuthenticationError, 'Invalid tenant_id format in JWT payload'
        end
      end

      # Company group domain should be string (if present)
      if @config.validate_subdomain?
        subdomain = payload[@config.payload_key(:subdomain).to_s]
        if subdomain.to_s.empty? || !subdomain.is_a?(String)
          raise AuthenticationError, 'Invalid subdomain format in JWT payload'
        end
      end

      # Company slugs should be array (if present)
      return unless @config.validate_pathname_slug?

      pathname_slugs = payload[@config.payload_key(:pathname_slugs).to_s]
      return unless pathname_slugs && !pathname_slugs.is_a?(Array)

      raise AuthenticationError, 'Invalid pathname_slugs format in JWT payload - must be array'
    end
  end
end
