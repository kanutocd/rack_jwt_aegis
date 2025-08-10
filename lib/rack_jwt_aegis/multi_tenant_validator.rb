# frozen_string_literal: true

module RackJwtAegis
  class MultiTenantValidator
    def initialize(config)
      @config = config
    end

    def validate(request, payload)
      validate_subdomain(request, payload) if @config.validate_subdomain?
      validate_pathname_slug(request, payload) if @config.validate_pathname_slug?
      validate_company_header(request, payload) if @config.tenant_id_header_name
    end

    private

    # Level 1 Multi-Tenant: Top-level tenant (Company-Group) validation via subdomain
    def validate_subdomain(request, payload)
      request_host = request.host
      return if request_host.nil? || request_host.empty?

      # Extract subdomain from request host
      request_subdomain = extract_subdomain(request_host)

      # Get JWT domain claim
      jwt_domain_key = @config.payload_key(:subdomain).to_s
      jwt_domain = payload[jwt_domain_key]

      if jwt_domain.nil? || jwt_domain.empty?
        raise AuthorizationError, 'JWT payload missing subdomain for subdomain validation'
      end

      # Extract subdomain from JWT domain
      jwt_subdomain = extract_subdomain(jwt_domain)

      # Compare subdomains
      return if subdomains_match?(request_subdomain, jwt_subdomain)

      raise AuthorizationError,
            "Subdomain access denied: request subdomain '#{request_subdomain}' does not match JWT subdomain '#{jwt_subdomain}'"
    end

    # Level 2 Multi-Tenant: Sub-level tenant (Company) validation via URL path
    def validate_pathname_slug(request, payload)
      # Extract company slug from URL path
      company_slug = extract_company_slug_from_path(request.path)

      return if company_slug.nil? # No company slug in path

      # Get accessible company slugs from JWT
      jwt_slugs_key = @config.payload_key(:pathname_slugs).to_s
      accessible_slugs = payload[jwt_slugs_key]

      if accessible_slugs.nil? || !accessible_slugs.is_a?(Array) || accessible_slugs.empty?
        raise AuthorizationError, 'JWT payload missing or invalid pathname_slugs for company access validation'
      end

      # Check if requested company slug is in user's accessible list
      return if accessible_slugs.include?(company_slug)

      raise AuthorizationError,
            "Company access denied: '#{company_slug}' not in accessible companies #{accessible_slugs}"
    end

    # Company Group header validation (additional security layer)
    def validate_company_header(request, payload)
      header_name = "HTTP_#{@config.tenant_id_header_name.upcase.tr('-', '_')}"
      header_value = request.get_header(header_name)

      return if header_value.nil? # Header not present, skip validation

      # Get company group ID from JWT
      jwt_company_group_key = @config.payload_key(:tenant_id).to_s
      jwt_tenant_id = payload[jwt_company_group_key]

      raise AuthorizationError, 'JWT payload missing tenant_id for header validation' if jwt_tenant_id.nil?

      # Normalize values for comparison (both as strings)
      header_value_str = header_value.to_s
      jwt_value_str = jwt_tenant_id.to_s

      return if header_value_str == jwt_value_str

      raise AuthorizationError,
            "Company group header mismatch: header '#{header_value_str}' does not match JWT '#{jwt_value_str}'"
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

    def extract_company_slug_from_path(path)
      return nil if path.nil? || path.empty?

      # Use configured pattern to extract company slug
      match = @config.pathname_slug_pattern.match(path)
      return nil unless match && match[1]

      # Return captured group (company slug)
      match[1]
    end

    def subdomains_match?(first_subdomain, second_subdomain)
      # Handle nil cases
      return true if first_subdomain.nil? && second_subdomain.nil?
      return false if first_subdomain.nil? || second_subdomain.nil?

      # Case-insensitive comparison
      first_subdomain.downcase == second_subdomain.downcase
    end
  end
end
