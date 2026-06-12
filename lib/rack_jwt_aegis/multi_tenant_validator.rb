# frozen_string_literal: true

module RackJwtAegis
  # Multi-tenant validation for subdomain and pathname slug access control
  #
  # Validates that users can only access resources within their permitted
  # tenant boundaries. Supports two levels of tenant validation:
  # 1. Subdomain-based (Level 1) - Company-Group level isolation
  # 2. Pathname slug-based (Level 2) - Company level isolation within groups
  #
  # @author Ken Camajalan Demanawa
  # @since 0.1.0
  #
  # @example Usage
  #   config = Configuration.new(
  #     jwt_secret: 'secret',
  #     validate_subdomain: true,
  #     validate_pathname_slug: true
  #   )
  #   validator = MultiTenantValidator.new(config)
  #   validator.validate(request, jwt_payload)
  class MultiTenantValidator
    # Initialize the multi-tenant validator
    #
    # @param config [Configuration] the configuration instance
    def initialize(config)
      @config = config
    end

    # Validate multi-tenant access permissions for the request
    #
    # @param request [Rack::Request] the incoming request
    # @param payload [Hash] the JWT payload containing tenant information
    # @raise [AuthorizationError] if tenant validation fails
    def validate(request, payload)
      validate_authentication_headers(request, payload)
      validate_subdomain(request, payload)
      validate_pathname_slug(request, payload)
      validate_tenant_id_header(request, payload)
    end

    private

    def validate_authentication_headers(request, payload)
      return unless @config.require_authentication_headers?

      validate_header_claim_match(
        request,
        payload,
        header_name: @config.tenant_id_header_name,
        claim_name: @config.payload_key(:tenant_id),
        label: 'tenant id',
      )

      validate_header_claim_match(
        request,
        payload,
        header_name: @config.tenant_slug_header_name,
        claim_name: @config.payload_key(:tenant_slug),
        label: 'tenant slug',
      )

      validate_header_claim_match(
        request,
        payload,
        header_name: @config.user_id_header_name,
        claim_name: @config.payload_key(:user_id),
        label: 'user id',
      )
    end

    # Level 1 Multi-Tenant: Top-level tenant (Company-Group) validation via subdomain
    def validate_subdomain(request, payload)
      return unless @config.validate_subdomain?

      request_host = request.host
      return if request_host.to_s.empty?

      # Extract subdomain from request host
      req_subdomain = extract_subdomain(request_host).to_s.downcase

      # Get JWT domain claim
      jwt_claim = payload[@config.payload_key(:subdomain).to_s].to_s.strip.downcase
      raise AuthorizationError, 'JWT payload missing subdomain for subdomain validation' if jwt_claim.empty?

      # Compare subdomains
      return if req_subdomain.eql?(jwt_claim)

      raise AuthorizationError,
            "Subdomain access denied: request subdomain '#{req_subdomain}' " \
            "does not match JWT subdomain '#{jwt_claim}'"
    end

    # Level 2 Multi-Tenant: Sub-level tenant (Company) validation via URL path
    def validate_pathname_slug(request, payload)
      return unless @config.validate_pathname_slug?

      # Extract company slug from URL path
      pathname_slug = extract_slug_from_path(request.path)

      return if pathname_slug.nil? # No company slug in path

      # Get accessible company slugs from JWT
      accessible_slugs = payload[@config.payload_key(:pathname_slugs).to_s]

      if accessible_slugs.nil? || !accessible_slugs.is_a?(Array) || accessible_slugs.empty?
        raise AuthorizationError, 'JWT payload missing or invalid pathname_slugs for pathname slug access validation'
      end

      # Check if requested company slug is in user's accessible list
      return if accessible_slugs.map(&:downcase).include?(pathname_slug)

      # TODO: make this error configurable as well
      raise AuthorizationError,
            "Pathname slug access denied: '#{pathname_slug}' not in accessible pathname slugs #{accessible_slugs}"
    end

    # Company Group header validation (additional security layer)
    def validate_tenant_id_header(request, payload)
      return unless @config.validate_tenant_id?

      # Get tenant id from request header
      header_value = request.get_header("HTTP_#{@config.tenant_id_header_name.upcase.tr('-', '_')}").to_s.downcase
      # Get tenant id from JWT payload
      jwt_claim = payload[@config.payload_key(:tenant_id).to_s].to_s.strip.downcase
      raise AuthorizationError, 'JWT payload missing tenant_id for header validation' if jwt_claim.empty?

      return if !header_value.empty? && header_value.eql?(jwt_claim)

      raise AuthorizationError,
            "Tenant id header mismatch: header '#{header_value}' does not match JWT '#{jwt_claim}'"
    end

    def validate_header_claim_match(request, payload, header_name:, claim_name:, label:)
      header_value = header_value(request, header_name)
      raise AuthorizationError, "Required authentication header missing: #{header_name}" if header_value.empty?

      jwt_claim = payload[claim_name.to_s].to_s.strip.downcase
      raise AuthorizationError, "JWT payload missing #{claim_name} for #{label} header validation" if jwt_claim.empty?

      return if header_value.eql?(jwt_claim)

      raise AuthorizationError,
            "#{label.capitalize} header mismatch: header '#{header_value}' does not match JWT '#{jwt_claim}'"
    end

    def header_value(request, header_name)
      request.get_header("HTTP_#{header_name.upcase.tr('-', '_')}").to_s.strip.downcase
    end

    def extract_subdomain(host)
      return nil if host.nil? || host.empty?

      # Handle different host formats:
      # - subdomain.domain.com -> subdomain
      # - subdomain.domain.co.uk -> subdomain
      # - domain.com -> nil (no subdomain)
      # - localhost:3000 -> nil (no subdomain)

      parts = host.split('.')

      # Need at least 3 parts for subdomain (subdomain.domain.tld)
      # or 4 parts for country domains (subdomain.domain.co.uk)
      return nil if parts.length < 3

      # Return first part as subdomain
      parts.first
    end

    def extract_slug_from_path(path)
      # Use configured pattern to extract company slug
      @config.pathname_slug_pattern.match(path.to_s.strip.downcase)&.to_a&.last
    end
  end
end
