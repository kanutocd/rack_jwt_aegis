# frozen_string_literal: true

require 'test_helper'

class RbacManagerSimplifiedTest < Minitest::Test
  def setup
    @config = RackJwtAegis::Configuration.new(
      basic_config.merge(
        rbac_cache_store: :memory,
        cache_write_enabled: false, # Disable permission caching to test RBAC directly
      ),
    )
    @manager = RackJwtAegis::RbacManager.new(@config)
    @request = rack_request(method: 'GET', path: '/api/users')
  end

  def test_authorize_rbac_permission_true_boolean
    payload = valid_jwt_payload
    rbac_key = @manager.send(:build_rbac_key, 123, @request.host, @request.path, @request.request_method)
    rbac_cache = @manager.instance_variable_get(:@rbac_cache)

    rbac_cache.write(rbac_key, true)
    # Should not raise an error
    @manager.authorize(@request, payload)
  end

  def test_authorize_rbac_permission_string_true
    payload = valid_jwt_payload
    rbac_key = @manager.send(:build_rbac_key, 123, @request.host, @request.path, @request.request_method)
    rbac_cache = @manager.instance_variable_get(:@rbac_cache)

    rbac_cache.write(rbac_key, 'true')
    # Should not raise an error
    @manager.authorize(@request, payload)
  end

  def test_authorize_rbac_permission_integer_1
    payload = valid_jwt_payload
    rbac_key = @manager.send(:build_rbac_key, 123, @request.host, @request.path, @request.request_method)
    rbac_cache = @manager.instance_variable_get(:@rbac_cache)

    rbac_cache.write(rbac_key, 1)
    # Should not raise an error
    @manager.authorize(@request, payload)
  end

  def test_authorize_rbac_permission_string_1
    payload = valid_jwt_payload
    rbac_key = @manager.send(:build_rbac_key, 123, @request.host, @request.path, @request.request_method)
    rbac_cache = @manager.instance_variable_get(:@rbac_cache)

    rbac_cache.write(rbac_key, '1')
    # Should not raise an error
    @manager.authorize(@request, payload)
  end

  def test_authorize_complex_hash_permission_with_allowed_methods
    payload = valid_jwt_payload
    rbac_key = @manager.send(:build_rbac_key, 123, @request.host, @request.path, @request.request_method)
    rbac_cache = @manager.instance_variable_get(:@rbac_cache)

    rbac_cache.write(rbac_key, { 'allowed_methods' => ['GET', 'POST'] })
    # Should not raise an error for GET request
    @manager.authorize(@request, payload)
  end

  def test_authorize_complex_hash_permission_with_roles
    payload = valid_jwt_payload
    rbac_key = @manager.send(:build_rbac_key, 123, @request.host, @request.path, @request.request_method)
    rbac_cache = @manager.instance_variable_get(:@rbac_cache)

    rbac_cache.write(rbac_key, { 'roles' => ['admin', 'user'] })
    # Should not raise an error (roles present means allowed)
    @manager.authorize(@request, payload)
  end

  def test_authorize_complex_hash_permission_allowed_true
    payload = valid_jwt_payload
    rbac_key = @manager.send(:build_rbac_key, 123, @request.host, @request.path, @request.request_method)
    rbac_cache = @manager.instance_variable_get(:@rbac_cache)

    rbac_cache.write(rbac_key, { 'allowed' => true })
    # Should not raise an error
    @manager.authorize(@request, payload)
  end

  def test_authorize_complex_array_permission_allowed
    payload = valid_jwt_payload
    rbac_key = @manager.send(:build_rbac_key, 123, @request.host, @request.path, @request.request_method)
    rbac_cache = @manager.instance_variable_get(:@rbac_cache)

    rbac_cache.write(rbac_key, ['GET', 'POST'])
    # Should not raise an error for GET request
    @manager.authorize(@request, payload)
  end

  def skip_test_stale_cached_permission_flow
    # Skip - permission cache disabled in this setup
  end
end
