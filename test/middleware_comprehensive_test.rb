# frozen_string_literal: true

require 'test_helper'

class MiddlewareComprehensiveTest < Minitest::Test
  def setup
    @app = ->(_env) { [200, {}, ['OK']] }
  end

  def test_initialization_with_rbac_enabled
    config = {
      jwt_secret: 'test-secret',
      rbac_enabled: true,
      rbac_cache_store: :memory,
    }

    middleware = RackJwtAegis::Middleware.new(@app, config)

    rbac_manager = middleware.instance_variable_get(:@rbac_manager)

    assert_instance_of RackJwtAegis::RbacManager, rbac_manager
  end

  def test_initialization_with_multi_tenant_enabled
    config = {
      jwt_secret: 'test-secret',
      validate_subdomain: true,
    }

    middleware = RackJwtAegis::Middleware.new(@app, config)

    multi_tenant_validator = middleware.instance_variable_get(:@multi_tenant_validator)

    assert_instance_of RackJwtAegis::MultiTenantValidator, multi_tenant_validator
  end

  def test_initialization_basic_jwt_only
    config = { jwt_secret: 'test-secret' }

    middleware = RackJwtAegis::Middleware.new(@app, config)

    assert_nil middleware.instance_variable_get(:@multi_tenant_validator)
    assert_nil middleware.instance_variable_get(:@rbac_manager)
  end

  def test_custom_payload_validation_success
    config = {
      jwt_secret: 'test-secret',
      custom_payload_validator: ->(payload, _request) {
        payload['role'] == 'admin'
      },
    }

    middleware = RackJwtAegis::Middleware.new(@app, config)

    env = Rack::MockRequest.env_for(
      'http://example.com/api/users',
      'HTTP_AUTHORIZATION' => "Bearer #{generate_jwt_token({ 'user_id' => 123, 'role' => 'admin' })}",
    )

    status, _headers, _body = middleware.call(env)

    assert_equal 200, status
  end

  def test_custom_payload_validation_failure
    config = {
      jwt_secret: 'test-secret',
      custom_payload_validator: ->(payload, _request) {
        payload['role'] == 'admin'
      },
    }

    middleware = RackJwtAegis::Middleware.new(@app, config)

    env = Rack::MockRequest.env_for(
      'http://example.com/api/users',
      'HTTP_AUTHORIZATION' => "Bearer #{generate_jwt_token({ 'user_id' => 123, 'role' => 'user' })}",
    )

    status, _headers, body = middleware.call(env)

    assert_equal 403, status

    response_data = JSON.parse(body.first)

    assert_equal 'Custom validation failed', response_data['error']
  end

  def test_standard_error_handling_with_debug_mode
    config = {
      jwt_secret: 'test-secret',
      debug_mode: true,
    }

    # Mock app that raises an error
    error_app = ->(_env) { raise StandardError, 'Something went wrong' }
    middleware = RackJwtAegis::Middleware.new(error_app, config)

    env = Rack::MockRequest.env_for(
      'http://example.com/api/users',
      'HTTP_AUTHORIZATION' => "Bearer #{generate_jwt_token}",
    )

    status, _headers, body = middleware.call(env)

    assert_equal 500, status

    response_data = JSON.parse(body.first)

    assert_match(/Internal error: Something went wrong/, response_data['error'])
  end

  def test_standard_error_handling_without_debug_mode
    config = {
      jwt_secret: 'test-secret',
      debug_mode: false,
    }

    # Mock app that raises an error
    error_app = ->(_env) { raise StandardError, 'Something went wrong' }
    middleware = RackJwtAegis::Middleware.new(error_app, config)

    env = Rack::MockRequest.env_for(
      'http://example.com/api/users',
      'HTTP_AUTHORIZATION' => "Bearer #{generate_jwt_token}",
    )

    status, _headers, body = middleware.call(env)

    assert_equal 500, status

    response_data = JSON.parse(body.first)

    assert_equal 'Internal server error', response_data['error']
  end

  def test_extract_jwt_token_empty_header
    config = { jwt_secret: 'test-secret' }
    middleware = RackJwtAegis::Middleware.new(@app, config)

    env = Rack::MockRequest.env_for('http://example.com/api/users')

    status, _headers, body = middleware.call(env)

    assert_equal 401, status

    response_data = JSON.parse(body.first)

    assert_equal 'Authorization header missing', response_data['error']
  end

  def test_extract_jwt_token_invalid_format
    config = { jwt_secret: 'test-secret' }
    middleware = RackJwtAegis::Middleware.new(@app, config)

    env = Rack::MockRequest.env_for(
      'http://example.com/api/users',
      'HTTP_AUTHORIZATION' => 'Basic username:password',
    )

    status, _headers, body = middleware.call(env)

    assert_equal 401, status

    response_data = JSON.parse(body.first)

    assert_equal 'Invalid authorization header format', response_data['error']
  end

  def test_extract_jwt_token_missing_token
    config = { jwt_secret: 'test-secret' }
    middleware = RackJwtAegis::Middleware.new(@app, config)

    env = Rack::MockRequest.env_for(
      'http://example.com/api/users',
      'HTTP_AUTHORIZATION' => 'Bearer',
    )

    status, _headers, body = middleware.call(env)

    assert_equal 401, status

    response_data = JSON.parse(body.first)

    assert_equal 'Invalid authorization header format', response_data['error']
  end

  def test_enabled_features_all_disabled
    config = { jwt_secret: 'test-secret' }
    middleware = RackJwtAegis::Middleware.new(@app, config)

    features = middleware.send(:enabled_features)

    assert_equal 'JWT', features
  end

  def test_enabled_features_all_enabled
    config = {
      jwt_secret: 'test-secret',
      validate_tenant_id: true,
      validate_subdomain: true,
      validate_pathname_slug: true,
      rbac_enabled: true,
      rbac_cache_store: :memory,
    }
    middleware = RackJwtAegis::Middleware.new(@app, config)

    features = middleware.send(:enabled_features)

    assert_equal 'JWT, TenantId, Subdomain, PathnameSlug, RBAC', features
  end

  def test_debug_log_enabled
    config = {
      jwt_secret: 'test-secret',
      debug_mode: true,
    }
    middleware = RackJwtAegis::Middleware.new(@app, config)

    # Capture stdout
    output = capture_io do
      middleware.send(:debug_log, 'Test message')
    end

    assert_match(/Middleware: Test message/, output.first)
  end

  def test_debug_log_disabled
    config = {
      jwt_secret: 'test-secret',
      debug_mode: false,
    }
    middleware = RackJwtAegis::Middleware.new(@app, config)

    # Capture stdout
    output = capture_io do
      middleware.send(:debug_log, 'Test message')
    end

    assert_empty output.first
  end

  def test_multi_tenant_enabled_with_subdomain_only
    config = {
      jwt_secret: 'test-secret',
      validate_subdomain: true,
      validate_pathname_slug: false,
    }
    middleware = RackJwtAegis::Middleware.new(@app, config)

    assert middleware.send(:multi_tenant_enabled?)
  end

  def test_multi_tenant_enabled_with_pathname_slug_only
    config = {
      jwt_secret: 'test-secret',
      validate_subdomain: false,
      validate_pathname_slug: true,
    }
    middleware = RackJwtAegis::Middleware.new(@app, config)

    assert middleware.send(:multi_tenant_enabled?)
  end

  def test_multi_tenant_disabled
    config = {
      jwt_secret: 'test-secret',
      validate_subdomain: false,
      validate_pathname_slug: false,
    }
    middleware = RackJwtAegis::Middleware.new(@app, config)

    refute middleware.send(:multi_tenant_enabled?)
  end

  def test_skip_path_functionality
    config = {
      jwt_secret: 'test-secret',
      skip_paths: ['/health', '/api/v1/public/info'],
    }
    middleware = RackJwtAegis::Middleware.new(@app, config)

    # Test exact path match
    env = Rack::MockRequest.env_for('http://example.com/health')
    status, _headers, _body = middleware.call(env)

    assert_equal 200, status

    # Test another exact path match
    env = Rack::MockRequest.env_for('http://example.com/api/v1/public/info')
    status, _headers, _body = middleware.call(env)

    assert_equal 200, status
  end

  def test_request_context_set_successfully
    config = { jwt_secret: 'test-secret' }
    middleware = RackJwtAegis::Middleware.new(@app, config)

    payload = { 'user_id' => 123, 'role' => 'admin' }
    env = Rack::MockRequest.env_for(
      'http://example.com/api/users',
      'HTTP_AUTHORIZATION' => "Bearer #{generate_jwt_token(payload)}",
    )

    status, _headers, _body = middleware.call(env)

    assert_equal 200, status

    # Verify context was set
    assert env[RackJwtAegis::RequestContext::AUTHENTICATED_KEY]
    assert_equal payload, env[RackJwtAegis::RequestContext::JWT_PAYLOAD_KEY]
    assert_equal 123, env[RackJwtAegis::RequestContext::USER_ID_KEY]
  end

  def test_extract_user_roles_with_roles_array
    config = {
      jwt_secret: 'test-secret',
      rbac_enabled: true,
      rbac_cache_store: :memory,
    }
    middleware = RackJwtAegis::Middleware.new(@app, config)

    payload = { 'roles' => ['admin', 'user', 123] }
    roles = middleware.send(:extract_user_roles, payload)

    assert_equal ['admin', 'user', '123'], roles
  end

  def test_extract_user_roles_with_single_role_string
    config = {
      jwt_secret: 'test-secret',
      rbac_enabled: true,
      rbac_cache_store: :memory,
    }
    middleware = RackJwtAegis::Middleware.new(@app, config)

    payload = { 'role' => 'admin' }
    roles = middleware.send(:extract_user_roles, payload)

    assert_equal ['admin'], roles
  end

  def test_extract_user_roles_with_single_role_integer
    config = {
      jwt_secret: 'test-secret',
      rbac_enabled: true,
      rbac_cache_store: :memory,
    }
    middleware = RackJwtAegis::Middleware.new(@app, config)

    payload = { 'user_roles' => 123 }
    roles = middleware.send(:extract_user_roles, payload)

    assert_equal ['123'], roles
  end

  def test_extract_user_roles_with_role_ids
    config = {
      jwt_secret: 'test-secret',
      rbac_enabled: true,
      rbac_cache_store: :memory,
    }
    middleware = RackJwtAegis::Middleware.new(@app, config)

    payload = { 'role_ids' => [1, 2, 3] }
    roles = middleware.send(:extract_user_roles, payload)

    assert_equal ['1', '2', '3'], roles
  end

  def test_extract_user_roles_with_no_roles
    config = {
      jwt_secret: 'test-secret',
      rbac_enabled: true,
      rbac_cache_store: :memory,
      debug_mode: true,
    }
    middleware = RackJwtAegis::Middleware.new(@app, config)

    payload = { 'user_id' => 123, 'some_other_field' => 'value' }

    # Capture debug log output
    output = capture_io do
      roles = middleware.send(:extract_user_roles, payload)

      assert_empty roles
    end

    assert_match(/Warning: No valid roles found in JWT payload/, output.first)
  end

  def test_extract_user_roles_with_invalid_type
    config = {
      jwt_secret: 'test-secret',
      rbac_enabled: true,
      rbac_cache_store: :memory,
      debug_mode: true,
    }
    middleware = RackJwtAegis::Middleware.new(@app, config)

    payload = { 'roles' => { 'invalid' => 'hash' } }

    # Capture debug log output
    output = capture_io do
      roles = middleware.send(:extract_user_roles, payload)

      assert_empty roles
    end

    assert_match(/Warning: No valid roles found in JWT payload/, output.first)
  end

  def test_extract_jwt_token_with_only_whitespace_after_bearer
    config = { jwt_secret: 'test-secret' }
    middleware = RackJwtAegis::Middleware.new(@app, config)

    # The regex (.+) actually will match spaces, so this should match and extract the spaces
    # But then the token.empty? check should trigger "JWT token missing"
    # Let me use newlines or tabs which might be treated as empty when trimmed
    env = Rack::MockRequest.env_for(
      'http://example.com/api/users',
      'HTTP_AUTHORIZATION' => "Bearer \t\n ", # Tab and newline
    )

    status, _headers, body = middleware.call(env)

    assert_equal 401, status

    response_data = JSON.parse(body.first)

    # The regex will match, but JWT validation will fail
    assert_match(/Invalid JWT token/, response_data['error'])
  end

  def test_extract_jwt_token_bearer_without_space
    config = { jwt_secret: 'test-secret' }
    middleware = RackJwtAegis::Middleware.new(@app, config)

    # Test edge case: "Bearer" without any space or token
    env = Rack::MockRequest.env_for(
      'http://example.com/api/users',
      'HTTP_AUTHORIZATION' => 'Bearer',
    )

    status, _headers, body = middleware.call(env)

    assert_equal 401, status

    response_data = JSON.parse(body.first)

    assert_equal 'Invalid authorization header format', response_data['error']
  end

  def test_empty_authorization_header_string
    config = { jwt_secret: 'test-secret' }
    middleware = RackJwtAegis::Middleware.new(@app, config)

    # Test with empty string authorization header
    env = Rack::MockRequest.env_for(
      'http://example.com/api/users',
      'HTTP_AUTHORIZATION' => '',
    )

    status, _headers, body = middleware.call(env)

    assert_equal 401, status

    response_data = JSON.parse(body.first)

    assert_equal 'Authorization header missing', response_data['error']
  end

  def test_rbac_user_roles_extraction_and_setting
    config = {
      jwt_secret: 'test-secret',
      rbac_enabled: true,
      rbac_cache_store: :memory,
      cache_write_enabled: true,
      payload_mapping: { role_ids: :roles },
    }
    middleware = RackJwtAegis::Middleware.new(@app, config)

    # Mock RBAC manager to allow the request
    rbac_manager = middleware.instance_variable_get(:@rbac_manager)
    rbac_manager.stubs(:authorize).returns(true)

    payload = { 'user_id' => 123, 'roles' => ['admin', 'user'] }
    env = Rack::MockRequest.env_for(
      'http://example.com/api/users',
      'HTTP_AUTHORIZATION' => "Bearer #{generate_jwt_token(payload)}",
    )

    status, _headers, _body = middleware.call(env)

    assert_equal 200, status

    # Verify user roles were set in environment
    assert_equal ['admin', 'user'], env['rack_jwt_aegis.user_roles']
  end

  private

  def capture_io
    require 'stringio'
    old_stdout = $stdout
    $stdout = captured_stdout = StringIO.new

    begin
      yield
      [captured_stdout.string]
    ensure
      $stdout = old_stdout
    end
  end
end
