# frozen_string_literal: true

require 'test_helper'

class RbacIntegrationTest < Minitest::Test
  def setup
    @config = RackJwtAegis::Configuration.new(
      jwt_secret: 'test-secret',
      rbac_enabled: true,
      rbac_cache_store: :memory,
    )

    @app = ->(_env) do
      [200, { 'Content-Type' => 'application/json' }, ['{"message": "success"}']]
    end

    @middleware = RackJwtAegis::Middleware.new(@app, @config.instance_variables.each_with_object({}) do |var, hash|
      hash[var.to_s.delete('@').to_sym] = @config.instance_variable_get(var)
    end)

    # Setup RBAC cache with the user's specified format
    # We need to get the cache from the middleware's RBAC manager to ensure consistency
    rbac_manager = @middleware.instance_variable_get(:@rbac_manager)
    rbac_cache = rbac_manager.instance_variable_get(:@rbac_cache)

    # Cache the RBAC permissions in the format specified by the user:
    # {last_update: 1234567890, permissions: [{role-id: ["sales/invoices:get", ...]}]}
    rbac_data = {
      'last_update' => Time.now.to_i,
      'permissions' => [
        {
          '1' => ['sales/invoices:get', 'sales/invoices:post'], # Role ID 1
          '2' => ['%r{.*}:*'], # Role ID 2 (super admin - any resource, any method)
        },
      ],
    }

    rbac_cache.write('permissions', rbac_data)
  end

  def test_rbac_authorization_with_valid_role_ids
    # Create JWT payload with role_ids that match cached permissions
    payload = {
      'user_id' => '123',
      'role_ids' => ['1', '2'], # User has both role 1 and 2
    }

    token = JWT.encode(payload, 'test-secret', 'HS256')

    # Test request to sales/invoices with GET method (allowed by role 1)
    env = create_env('GET', '/api/v1/test-company/sales/invoices', token)

    status, _headers, body = @middleware.call(env)

    assert_equal 200, status
    assert_includes body.first, 'success'
  end

  def test_rbac_authorization_with_admin_wildcard
    payload = {
      'user_id' => '123',
      'role_ids' => ['2'], # User has admin role (role 2)
    }

    token = JWT.encode(payload, 'test-secret', 'HS256')

    # Test request to any endpoint with any method (allowed by admin/* wildcard)
    env = create_env('DELETE', '/api/v1/test-company/users/456', token)

    status, _headers, body = @middleware.call(env)

    assert_equal 200, status
    assert_includes body.first, 'success'
  end

  def test_rbac_authorization_denied_for_insufficient_permissions
    payload = {
      'user_id' => '123',
      'role_ids' => ['1'], # User only has role 1 (sales permissions)
    }

    token = JWT.encode(payload, 'test-secret', 'HS256')

    # Test request to admin endpoint (not allowed by role 1)
    env = create_env('DELETE', '/api/v1/test-company/admin/settings', token)

    status, _headers, body = @middleware.call(env)

    assert_equal 403, status
    response = JSON.parse(body.first)

    assert_includes response['error'], 'Access denied'
  end

  def test_rbac_with_custom_role_ids_mapping
    config = RackJwtAegis::Configuration.new(
      jwt_secret: 'test-secret',
      rbac_enabled: true,
      rbac_cache_store: :memory,
      payload_mapping: { role_ids: :user_roles }, # Custom mapping
    )

    middleware = RackJwtAegis::Middleware.new(@app, config.instance_variables.each_with_object({}) do |var, hash|
      hash[var.to_s.delete('@').to_sym] = config.instance_variable_get(var)
    end)

    # Setup RBAC cache for this middleware instance
    rbac_manager = middleware.instance_variable_get(:@rbac_manager)
    rbac_cache = rbac_manager.instance_variable_get(:@rbac_cache)
    rbac_data = {
      'last_update' => Time.now.to_i,
      'permissions' => [{ '1' => ['sales/invoices:get'] }],
    }
    rbac_cache.write('permissions', rbac_data)

    # JWT payload uses custom field name 'user_roles' instead of 'role_ids'
    payload = {
      'user_id' => '123',
      'user_roles' => ['1'], # Using custom mapping
    }

    token = JWT.encode(payload, 'test-secret', 'HS256')
    env = create_env('GET', '/api/v1/test-company/sales/invoices', token)

    status, _headers, body = middleware.call(env)

    assert_equal 200, status
    assert_includes body.first, 'success'
  end

  private

  def create_env(method, path, token)
    {
      'REQUEST_METHOD' => method,
      'PATH_INFO' => path,
      'HTTP_HOST' => 'test.example.com',
      'HTTP_AUTHORIZATION' => "Bearer #{token}",
      'rack.input' => StringIO.new,
      'rack.errors' => StringIO.new,
    }
  end
end
