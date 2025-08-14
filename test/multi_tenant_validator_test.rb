# frozen_string_literal: true

require 'test_helper'

class MultiTenantValidatorTest < Minitest::Test
  def setup
    @config = RackJwtAegis::Configuration.new(basic_config.merge(
                                                validate_subdomain: true,
                                                validate_pathname_slug: true,
                                                tenant_id_header_name: 'X-Tenant-Id',
                                              ))
    @validator = RackJwtAegis::MultiTenantValidator.new(@config)
  end

  def test_validate_with_all_validations_enabled
    request = rack_request(
      method: 'GET',
      path: '/api/v1/acme-widgets/products',
      host: 'acme-corp.example.com',
      headers: { 'X-Tenant-Id' => '456' },
    )

    payload = {
      'user_id' => 123,
      'tenant_id' => 456,
      'subdomain' => 'acme-corp',
      'pathname_slugs' => ['acme-widgets', 'acme-services'],
    }

    # Should not raise an error
    @validator.validate(request, payload)
  end

  def test_validate_subdomain_success
    config = RackJwtAegis::Configuration.new(basic_config.merge(validate_subdomain: true))
    validator = RackJwtAegis::MultiTenantValidator.new(config)

    request = rack_request(host: 'acme-corp.example.com')
    payload = { 'subdomain' => 'acme-corp' }

    # Should not raise an error
    validator.validate(request, payload)
  end

  def test_validate_subdomain_missing_jwt_domain
    config = RackJwtAegis::Configuration.new(basic_config.merge(validate_subdomain: true))
    validator = RackJwtAegis::MultiTenantValidator.new(config)

    request = rack_request(host: 'acme-corp.example.com')
    payload = { 'user_id' => 123 } # No subdomain

    error = assert_raises(RackJwtAegis::AuthorizationError) do
      validator.validate(request, payload)
    end
    assert_equal 'JWT payload missing subdomain for subdomain validation', error.message
  end

  def test_validate_subdomain_empty_jwt_domain
    config = RackJwtAegis::Configuration.new(basic_config.merge(validate_subdomain: true))
    validator = RackJwtAegis::MultiTenantValidator.new(config)

    request = rack_request(host: 'acme-corp.example.com')
    payload = { 'subdomain' => '' }

    error = assert_raises(RackJwtAegis::AuthorizationError) do
      validator.validate(request, payload)
    end
    assert_equal 'JWT payload missing subdomain for subdomain validation', error.message
  end

  def test_validate_subdomain_mismatch
    config = RackJwtAegis::Configuration.new(basic_config.merge(validate_subdomain: true))
    validator = RackJwtAegis::MultiTenantValidator.new(config)

    request = rack_request(host: 'acme-corp.example.com')
    payload = { 'subdomain' => 'different-corp.example.com' }

    error = assert_raises(RackJwtAegis::AuthorizationError) do
      validator.validate(request, payload)
    end
    assert_match(/Subdomain access denied/, error.message)
    assert_match(/acme-corp/, error.message)
    assert_match(/different-corp/, error.message)
  end

  def test_validate_subdomain_case_insensitive
    config = RackJwtAegis::Configuration.new(basic_config.merge(validate_subdomain: true))
    validator = RackJwtAegis::MultiTenantValidator.new(config)

    request = rack_request(host: 'ACME-CORP.example.com')
    payload = { 'subdomain' => 'acme-corp' }

    # Should not raise an error (case insensitive)
    validator.validate(request, payload)
  end

  def test_validate_subdomain_nil_host
    config = RackJwtAegis::Configuration.new(basic_config.merge(validate_subdomain: true))
    validator = RackJwtAegis::MultiTenantValidator.new(config)

    request = rack_request(host: '')
    request.stubs(:host).returns(nil)
    payload = { 'subdomain' => 'acme-corp' }

    # Should skip validation when host is nil/empty
    validator.validate(request, payload)
  end

  def test_validate_pathname_slug_success
    config = RackJwtAegis::Configuration.new(basic_config.merge(validate_pathname_slug: true))
    validator = RackJwtAegis::MultiTenantValidator.new(config)

    request = rack_request(path: '/api/v1/acme-widgets/products')
    payload = { 'pathname_slugs' => ['acme-widgets', 'acme-services'] }

    # Should not raise an error
    validator.validate(request, payload)
  end

  def test_validate_pathname_slug_no_company_in_path
    config = RackJwtAegis::Configuration.new(basic_config.merge(validate_pathname_slug: true))
    validator = RackJwtAegis::MultiTenantValidator.new(config)

    request = rack_request(path: '/api/v1/public')
    payload = { 'pathname_slugs' => ['acme-widgets'] }

    # Should skip validation when no company slug in path
    validator.validate(request, payload)
  end

  def test_validate_pathname_slug_missing_accessible_slugs
    config = RackJwtAegis::Configuration.new(basic_config.merge(validate_pathname_slug: true))
    validator = RackJwtAegis::MultiTenantValidator.new(config)

    request = rack_request(path: '/api/v1/acme-widgets/products')
    payload = { 'user_id' => 123 } # No pathname_slugs

    error = assert_raises(RackJwtAegis::AuthorizationError) do
      validator.validate(request, payload)
    end
    assert_equal 'JWT payload missing or invalid pathname_slugs for pathname slug access validation', error.message
  end

  def test_validate_pathname_slug_invalid_slugs_not_array
    config = RackJwtAegis::Configuration.new(basic_config.merge(validate_pathname_slug: true))
    validator = RackJwtAegis::MultiTenantValidator.new(config)

    request = rack_request(path: '/api/v1/acme-widgets/products')
    payload = { 'pathname_slugs' => 'not-an-array' }

    error = assert_raises(RackJwtAegis::AuthorizationError) do
      validator.validate(request, payload)
    end
    assert_equal 'JWT payload missing or invalid pathname_slugs for pathname slug access validation', error.message
  end

  def test_validate_pathname_slug_empty_array
    config = RackJwtAegis::Configuration.new(basic_config.merge(validate_pathname_slug: true))
    validator = RackJwtAegis::MultiTenantValidator.new(config)

    request = rack_request(path: '/api/v1/acme-widgets/products')
    payload = { 'pathname_slugs' => [] }

    error = assert_raises(RackJwtAegis::AuthorizationError) do
      validator.validate(request, payload)
    end
    assert_equal 'JWT payload missing or invalid pathname_slugs for pathname slug access validation', error.message
  end

  def test_validate_pathname_slug_access_denied
    config = RackJwtAegis::Configuration.new(basic_config.merge(validate_pathname_slug: true))
    validator = RackJwtAegis::MultiTenantValidator.new(config)

    request = rack_request(path: '/api/v1/unauthorized-company/products')
    payload = { 'pathname_slugs' => ['acme-widgets', 'acme-services'] }

    error = assert_raises(RackJwtAegis::AuthorizationError) do
      validator.validate(request, payload)
    end
    assert_match(/Pathname slug access denied/, error.message)
    assert_match(/unauthorized-company/, error.message)
    assert_match(/\["acme-widgets", "acme-services"\]/, error.message)
  end

  def test_validate_tenant_id_success
    config = RackJwtAegis::Configuration.new(basic_config.merge(validate_tenant_id: true,
                                                                tenant_id_header_name: 'X-Tenant-Id'))
    validator = RackJwtAegis::MultiTenantValidator.new(config)

    request = rack_request(headers: { 'X-Tenant-Id' => '456' })
    payload = { 'tenant_id' => 456 }

    # Should not raise an error
    validator.validate(request, payload)
  end

  def test_validate_tenant_id_string_to_int_match
    config = RackJwtAegis::Configuration.new(basic_config.merge(tenant_id_header_name: 'X-Tenant-Id'))
    validator = RackJwtAegis::MultiTenantValidator.new(config)

    request = rack_request(headers: { 'X-Tenant-Id' => '456' })
    payload = { 'tenant_id' => 456 }

    # Should not raise an error (string '456' should match int 456)
    validator.validate(request, payload)
  end

  def test_validate_tenant_id_no_header
    config = RackJwtAegis::Configuration.new(basic_config.merge(tenant_id_header_name: 'X-Tenant-Id'))
    validator = RackJwtAegis::MultiTenantValidator.new(config)

    request = rack_request
    payload = { 'tenant_id' => 456 }

    # Should skip validation when header is not present
    validator.validate(request, payload)
  end

  def test_validate_tenant_id_missing_jwt_tenant_id
    config = RackJwtAegis::Configuration.new(basic_config.merge(validate_tenant_id: true,
                                                                tenant_id_header_name: 'X-Tenant-Id'))
    validator = RackJwtAegis::MultiTenantValidator.new(config)

    request = rack_request(headers: { 'X-Tenant-Id' => '456' })
    payload = { 'user_id' => 123 } # No tenant_id

    error = assert_raises(RackJwtAegis::AuthorizationError) do
      validator.validate(request, payload)
    end
    assert_equal 'JWT payload missing tenant_id for header validation', error.message
  end

  def test_validate_tenant_id_mismatch
    config = RackJwtAegis::Configuration.new(basic_config.merge(validate_tenant_id: true,
                                                                tenant_id_header_name: 'X-Tenant-Id'))
    validator = RackJwtAegis::MultiTenantValidator.new(config)

    request = rack_request(headers: { 'X-Tenant-Id' => '456' })
    payload = { 'tenant_id' => 789 }

    error = assert_raises(RackJwtAegis::AuthorizationError) do
      validator.validate(request, payload)
    end
    assert_match(/Tenant id header mismatch/, error.message)
    assert_match(/456.*789/, error.message)
  end

  def test_extract_subdomain
    validator = @validator

    assert_equal 'acme-corp', validator.send(:extract_subdomain, 'acme-corp.example.com')
    assert_equal 'sub', validator.send(:extract_subdomain, 'sub.domain.co.uk')
    assert_nil validator.send(:extract_subdomain, 'example.com') # No subdomain
    assert_nil validator.send(:extract_subdomain, 'localhost:3000') # No subdomain
    assert_nil validator.send(:extract_subdomain, '') # Empty
    assert_nil validator.send(:extract_subdomain, nil) # Nil
  end

  def test_extract_slug_from_path
    validator = @validator

    assert_equal 'acme-widgets', validator.send(:extract_slug_from_path, '/api/v1/acme-widgets/products')
    assert_equal 'company-a', validator.send(:extract_slug_from_path, '/api/v1/company-a/users/123')
    assert_equal 'company-b', validator.send(:extract_slug_from_path, '/api/v1/COMPANY-B/users/123')
    assert_nil validator.send(:extract_slug_from_path, '/api/v1/public') # No match
    assert_nil validator.send(:extract_slug_from_path, '/health') # No match
    assert_nil validator.send(:extract_slug_from_path, '') # Empty
    assert_nil validator.send(:extract_slug_from_path, nil) # Nil
  end

  def test_extract_pathname_slug_with_custom_pattern
    config = RackJwtAegis::Configuration.new(basic_config.merge(
                                               validate_pathname_slug: true,
                                               pathname_slug_pattern: %r{^/company/([^/]+)/},
                                             ))
    validator = RackJwtAegis::MultiTenantValidator.new(config)

    assert_equal 'acme', validator.send(:extract_slug_from_path, '/company/acme/dashboard')
    assert_nil validator.send(:extract_slug_from_path, '/api/v1/acme/products') # Doesn't match custom pattern
  end

  def test_validate_skips_disabled_validations
    config = RackJwtAegis::Configuration.new(basic_config.merge(
                                               validate_subdomain: false,
                                               validate_pathname_slug: false,
                                               tenant_id_header_name: nil,
                                             ))
    validator = RackJwtAegis::MultiTenantValidator.new(config)

    request = rack_request(
      host: 'wrong-domain.example.com',
      path: '/api/v1/unauthorized/data',
    )
    payload = { 'user_id' => 123 }

    # Should not raise any errors when all validations are disabled
    validator.validate(request, payload)
  end

  def test_validate_custom_payload_mapping
    config = RackJwtAegis::Configuration.new(basic_config.merge(
                                               validate_subdomain: true,
                                               validate_pathname_slug: true,
                                               tenant_id_header_name: 'X-Company-Group-Id',
                                               payload_mapping: {
                                                 subdomain: :company_group_domain,
                                                 pathname_slugs: :accessible_companies,
                                                 tenant_id: :company_group_id,
                                               },
                                             ))
    validator = RackJwtAegis::MultiTenantValidator.new(config)

    request = rack_request(
      host: 'acme-corp.example.com',
      path: '/api/v1/widgets-division/products',
      headers: { 'X-Company-Group-Id' => '789' },
    )

    payload = {
      'user_id' => 123,
      'company_group_id' => 789,
      'company_group_domain' => 'acme-corp',
      'accessible_companies' => ['widgets-division', 'services-division'],
    }
    # Should not raise an error with custom payload mapping
    validator.validate(request, payload)

    # Case insensitive matching of pathname slugs
    payload['accessible_companies'] = ['WIDGETS-DIVISION', 'services-division']
    validator.validate(request, payload)
  end

  def test_header_name_normalization
    config = RackJwtAegis::Configuration.new(basic_config.merge(tenant_id_header_name: 'X-Custom-Tenant-ID'))
    validator = RackJwtAegis::MultiTenantValidator.new(config)

    # Test that header name gets properly normalized to HTTP_X_CUSTOM_TENANT_ID
    request = rack_request(headers: { 'X-Custom-Tenant-ID' => '456' })
    payload = { 'tenant_id' => 456 }

    # Should not raise an error
    validator.validate(request, payload)
  end
end
