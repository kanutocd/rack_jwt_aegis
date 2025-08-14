# frozen_string_literal: true

require 'test_helper'

class RequestContextTest < Minitest::Test
  def setup
    @config = RackJwtAegis::Configuration.new(basic_config.merge(
                                                validate_tenant_id: true,
                                                validate_subdomain: true,
                                                validate_pathname_slug: true,
                                              ))
    @context = RackJwtAegis::RequestContext.new(@config)
  end

  def test_constants_defined
    assert_equal 'rack_jwt_aegis.payload', RackJwtAegis::RequestContext::JWT_PAYLOAD_KEY
    assert_equal 'rack_jwt_aegis.user_id', RackJwtAegis::RequestContext::USER_ID_KEY
    assert_equal 'rack_jwt_aegis.tenant_id', RackJwtAegis::RequestContext::TENANT_ID_KEY
    assert_equal 'rack_jwt_aegis.subdomain', RackJwtAegis::RequestContext::SUBDOMAIN_KEY
    assert_equal 'rack_jwt_aegis.pathname_slugs', RackJwtAegis::RequestContext::PATHNAME_SLUGS_KEY
    assert_equal 'rack_jwt_aegis.authenticated', RackJwtAegis::RequestContext::AUTHENTICATED_KEY
  end

  def test_set_context_full_payload
    env = {}
    payload = {
      'user_id' => 123,
      'tenant_id' => 456,
      'subdomain' => 'acme-corp.example.com',
      'pathname_slugs' => ['widgets', 'services'],
    }

    @context.set_context(env, payload)

    assert_equal payload, env[RackJwtAegis::RequestContext::JWT_PAYLOAD_KEY]
    assert env[RackJwtAegis::RequestContext::AUTHENTICATED_KEY]
    assert_equal 123, env[RackJwtAegis::RequestContext::USER_ID_KEY]
    assert_equal 456, env[RackJwtAegis::RequestContext::TENANT_ID_KEY]
    assert_equal 'acme-corp.example.com', env[RackJwtAegis::RequestContext::SUBDOMAIN_KEY]
    assert_equal ['widgets', 'services'], env[RackJwtAegis::RequestContext::PATHNAME_SLUGS_KEY]
  end

  def test_set_context_minimal_payload
    env = {}
    payload = { 'user_id' => 123 }

    @context.set_context(env, payload)

    assert_equal payload, env[RackJwtAegis::RequestContext::JWT_PAYLOAD_KEY]
    assert env[RackJwtAegis::RequestContext::AUTHENTICATED_KEY]
    assert_equal 123, env[RackJwtAegis::RequestContext::USER_ID_KEY]
  end

  def test_set_context_with_custom_payload_mapping
    config = RackJwtAegis::Configuration.new(basic_config.merge(
                                               validate_tenant_id: true,
                                               validate_subdomain: true,
                                               validate_pathname_slug: true,
                                               payload_mapping: {
                                                 user_id: :sub,
                                                 tenant_id: :company_group,
                                                 subdomain: :domain,
                                                 pathname_slugs: :accessible_companies,
                                               },
                                             ))
    context = RackJwtAegis::RequestContext.new(config)

    env = {}
    payload = {
      'sub' => 789,
      'company_group' => 101,
      'domain' => 'custom.example.com',
      'accessible_companies' => ['alpha', 'beta'],
    }

    context.set_context(env, payload)

    assert_equal 789, env[RackJwtAegis::RequestContext::USER_ID_KEY]
    assert_equal 101, env[RackJwtAegis::RequestContext::TENANT_ID_KEY]
    assert_equal 'custom.example.com', env[RackJwtAegis::RequestContext::SUBDOMAIN_KEY]
    assert_equal ['alpha', 'beta'], env[RackJwtAegis::RequestContext::PATHNAME_SLUGS_KEY]
  end

  def test_set_context_pathname_slugs_not_array
    env = {}
    payload = {
      'user_id' => 123,
      'pathname_slugs' => 'single-slug',
    }

    @context.set_context(env, payload)

    # Should convert single value to array
    assert_equal ['single-slug'], env[RackJwtAegis::RequestContext::PATHNAME_SLUGS_KEY]
  end

  def test_set_context_nil_pathname_slugs
    env = {}
    payload = {
      'user_id' => 123,
      'pathname_slugs' => nil,
    }

    @context.set_context(env, payload)

    # Should default to empty array
    assert_empty env[RackJwtAegis::RequestContext::PATHNAME_SLUGS_KEY]
  end

  def test_authenticated_class_method
    env = {}

    refute RackJwtAegis::RequestContext.authenticated?(env)

    env[RackJwtAegis::RequestContext::AUTHENTICATED_KEY] = true

    assert RackJwtAegis::RequestContext.authenticated?(env)

    env[RackJwtAegis::RequestContext::AUTHENTICATED_KEY] = false

    refute RackJwtAegis::RequestContext.authenticated?(env)
  end

  def test_payload_class_method
    env = {}
    payload = { 'user_id' => 123, 'role' => 'admin' }

    assert_nil RackJwtAegis::RequestContext.payload(env)

    env[RackJwtAegis::RequestContext::JWT_PAYLOAD_KEY] = payload

    assert_equal payload, RackJwtAegis::RequestContext.payload(env)
  end

  def test_user_id_class_method
    env = {}

    assert_nil RackJwtAegis::RequestContext.user_id(env)

    env[RackJwtAegis::RequestContext::USER_ID_KEY] = 456

    assert_equal 456, RackJwtAegis::RequestContext.user_id(env)
  end

  def test_tenant_id_class_method
    env = {}

    assert_nil RackJwtAegis::RequestContext.tenant_id(env)

    env[RackJwtAegis::RequestContext::TENANT_ID_KEY] = 789

    assert_equal 789, RackJwtAegis::RequestContext.tenant_id(env)
  end

  def test_subdomain_class_method
    env = {}

    assert_nil RackJwtAegis::RequestContext.subdomain(env)

    env[RackJwtAegis::RequestContext::SUBDOMAIN_KEY] = 'test.example.com'

    assert_equal 'test.example.com', RackJwtAegis::RequestContext.subdomain(env)
  end

  def test_pathname_slugs_class_method
    env = {}

    # Should default to empty array when not set
    assert_empty RackJwtAegis::RequestContext.pathname_slugs(env)

    env[RackJwtAegis::RequestContext::PATHNAME_SLUGS_KEY] = ['slug1', 'slug2']

    assert_equal ['slug1', 'slug2'], RackJwtAegis::RequestContext.pathname_slugs(env)

    # Should handle nil by returning empty array
    env[RackJwtAegis::RequestContext::PATHNAME_SLUGS_KEY] = nil

    assert_empty RackJwtAegis::RequestContext.pathname_slugs(env)
  end

  def test_current_user_id_class_method
    request = mock
    env = { RackJwtAegis::RequestContext::USER_ID_KEY => 321 }
    request.expects(:env).returns(env)

    assert_equal 321, RackJwtAegis::RequestContext.current_user_id(request)
  end

  def test_current_tenant_id_class_method
    request = mock
    env = { RackJwtAegis::RequestContext::TENANT_ID_KEY => 654 }
    request.expects(:env).returns(env)

    assert_equal 654, RackJwtAegis::RequestContext.current_tenant_id(request)
  end

  def test_has_company_access_class_method
    env = {}

    # No slugs set - should return false
    refute RackJwtAegis::RequestContext.has_pathname_slug_access?(env, 'acme-widgets')

    # Set some slugs
    env[RackJwtAegis::RequestContext::PATHNAME_SLUGS_KEY] = ['acme-widgets', 'acme-services']

    # Should return true for accessible slugs
    assert RackJwtAegis::RequestContext.has_pathname_slug_access?(env, 'acme-widgets')
    assert RackJwtAegis::RequestContext.has_pathname_slug_access?(env, 'acme-services')

    # Should return false for non-accessible slugs
    refute RackJwtAegis::RequestContext.has_pathname_slug_access?(env, 'unauthorized-company')
  end

  def test_set_tenant_context_subdomain_disabled
    config = RackJwtAegis::Configuration.new(basic_config.merge(
                                               validate_subdomain: false,
                                               validate_pathname_slug: true,
                                             ))
    context = RackJwtAegis::RequestContext.new(config)

    env = {}
    payload = {
      'user_id' => 123,
      'tenant_id' => 456,
      'subdomain' => 'acme-corp.example.com',
      'pathname_slugs' => ['widgets'],
    }

    context.set_context(env, payload)

    # Should not set subdomain when validate_subdomain is false
    assert_nil env[RackJwtAegis::RequestContext::SUBDOMAIN_KEY]
    # But should set pathname_slugs since validate_pathname_slug is true
    assert_equal ['widgets'], env[RackJwtAegis::RequestContext::PATHNAME_SLUGS_KEY]
  end

  def test_set_tenant_context_pathname_slug_disabled
    config = RackJwtAegis::Configuration.new(basic_config.merge(
                                               validate_subdomain: true,
                                               validate_pathname_slug: false,
                                             ))
    context = RackJwtAegis::RequestContext.new(config)

    env = {}
    payload = {
      'user_id' => 123,
      'tenant_id' => 456,
      'subdomain' => 'acme-corp.example.com',
      'pathname_slugs' => ['widgets'],
    }

    context.set_context(env, payload)

    # Should set subdomain when validate_subdomain is true
    assert_equal 'acme-corp.example.com', env[RackJwtAegis::RequestContext::SUBDOMAIN_KEY]
    # Should set pathname_slugs even when validate_pathname_slug is false because it's in the payload
    assert_equal ['widgets'], env[RackJwtAegis::RequestContext::PATHNAME_SLUGS_KEY]
  end

  def test_set_tenant_context_with_payload_mapping_but_no_validation
    config = RackJwtAegis::Configuration.new(basic_config.merge(
                                               validate_tenant_id: true,
                                               validate_subdomain: false,
                                               validate_pathname_slug: false,
                                               payload_mapping: {
                                                 tenant_id: :company_group,
                                                 pathname_slugs: :accessible_companies,
                                               },
                                             ))
    context = RackJwtAegis::RequestContext.new(config)

    env = {}
    payload = {
      'user_id' => 123,
      'company_group' => 999,
      'accessible_companies' => ['alpha', 'beta'],
    }

    context.set_context(env, payload)

    # Should set tenant_id and pathname_slugs because they're in payload_mapping
    assert_equal 999, env[RackJwtAegis::RequestContext::TENANT_ID_KEY]
    assert_equal ['alpha', 'beta'], env[RackJwtAegis::RequestContext::PATHNAME_SLUGS_KEY]
  end

  def test_integration_with_rack_request
    # Test integration with actual Rack request
    request = rack_request
    payload = {
      'user_id' => 999,
      'tenant_id' => 111,
      'subdomain' => 'integration.example.com',
      'pathname_slugs' => ['test-company'],
    }

    @context.set_context(request.env, payload)

    # Test class methods work with real request
    assert RackJwtAegis::RequestContext.authenticated?(request.env)
    assert_equal payload, RackJwtAegis::RequestContext.payload(request.env)
    assert_equal 999, RackJwtAegis::RequestContext.current_user_id(request)
    assert_equal 111, RackJwtAegis::RequestContext.current_tenant_id(request)
    assert RackJwtAegis::RequestContext.has_pathname_slug_access?(request.env, 'test-company')
    refute RackJwtAegis::RequestContext.has_pathname_slug_access?(request.env, 'unauthorized')
  end
end
