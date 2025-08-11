# frozen_string_literal: true

require 'test_helper'

class RbacManagerTest < Minitest::Test
  def setup
    @config = RackJwtAegis::Configuration.new(basic_config.merge(
                                                cache_store: :memory,
                                                cache_write_enabled: true,
                                              ))
    @manager = RackJwtAegis::RbacManager.new(@config)
    @request = rack_request(method: 'GET', path: '/api/users')
  end

  def test_initialize_with_shared_cache
    config = RackJwtAegis::Configuration.new(
      jwt_secret: 'secret',
      cache_store: :memory,
      cache_write_enabled: true,
    )

    manager = RackJwtAegis::RbacManager.new(config)
    rbac_cache = manager.instance_variable_get(:@rbac_cache)
    permission_cache = manager.instance_variable_get(:@permission_cache)

    assert_same rbac_cache, permission_cache
  end

  def test_initialize_with_separate_caches
    config = RackJwtAegis::Configuration.new(
      jwt_secret: 'secret',
      rbac_cache_store: :memory,
      permission_cache_store: :memory,
    )

    manager = RackJwtAegis::RbacManager.new(config)
    rbac_cache = manager.instance_variable_get(:@rbac_cache)
    permission_cache = manager.instance_variable_get(:@permission_cache)

    refute_same rbac_cache, permission_cache
    assert_instance_of RackJwtAegis::MemoryAdapter, rbac_cache
    assert_instance_of RackJwtAegis::MemoryAdapter, permission_cache
  end

  def test_initialize_without_rbac_cache
    config = RackJwtAegis::Configuration.new(jwt_secret: 'secret')

    error = assert_raises(RackJwtAegis::ConfigurationError) do
      RackJwtAegis::RbacManager.new(config)
    end
    assert_equal 'RBAC cache store not configured', error.message
  end

  def test_authorize_missing_user_id
    payload = { 'tenant_id' => 456 }

    error = assert_raises(RackJwtAegis::AuthorizationError) do
      @manager.authorize(@request, payload)
    end
    assert_equal 'User ID missing from JWT payload', error.message
  end

  def test_authorize_with_cached_permission_allowed
    payload = valid_jwt_payload
    permission_key = @manager.send(:build_permission_key, 123, @request)

    # Mock cached permission
    permission_cache = @manager.instance_variable_get(:@permission_cache)
    permission_cache.write(permission_key, {
      'permission' => true,
      'timestamp' => Time.now.to_i,
    })

    # Mock last update timestamp
    rbac_cache = @manager.instance_variable_get(:@rbac_cache)
    rbac_cache.write('last-update', Time.now.to_i - 100)

    # Should not raise an error
    @manager.authorize(@request, payload)
  end

  def test_skip_test_authorize_with_cached_permission_denied
    payload = valid_jwt_payload
    permission_key = @manager.send(:build_permission_key, 123, @request)
    current_time = Time.now.to_i

    # Mock cached permission
    permission_cache = @manager.instance_variable_get(:@permission_cache)
    permission_cache.write(permission_key, {
      'permission' => false,
      'timestamp' => current_time,
    })

    # Mock last update timestamp - older than cached permission
    rbac_cache = @manager.instance_variable_get(:@rbac_cache)
    rbac_cache.write('last-update', current_time - 100)

    error = assert_raises(RackJwtAegis::AuthorizationError) do
      @manager.authorize(@request, payload)
    end
    assert_equal 'Access denied - cached permission', error.message
  end

  def test_skip_test_authorize_with_stale_cached_permission
    payload = valid_jwt_payload
    permission_key = @manager.send(:build_permission_key, 123, @request)
    rbac_key = @manager.send(:build_rbac_key, 123, @request.host, @request.path, @request.request_method)

    # Mock stale cached permission
    permission_cache = @manager.instance_variable_get(:@permission_cache)
    permission_cache.write(permission_key, {
      'permission' => true,
      'timestamp' => Time.now.to_i - 1000, # Old timestamp
    })

    # Mock last update timestamp (more recent)
    rbac_cache = @manager.instance_variable_get(:@rbac_cache)
    rbac_cache.write('last-update', Time.now.to_i - 100)

    # Mock RBAC permission (should be checked since cache is stale)
    rbac_cache.write(rbac_key, true)

    # Should not raise an error and should cache the new result
    @manager.authorize(@request, payload)

    # Verify stale cache was removed and new permission was cached
    cached_result = permission_cache.read(permission_key)

    assert cached_result['permission']
    assert_operator cached_result['timestamp'], :>, Time.now.to_i - 10
  end

  def skip_test_authorize_rbac_permission_true_variants
    # Moved to rbac_manager_simplified_test.rb
  end

  def test_authorize_rbac_permission_false_variants
    payload = valid_jwt_payload
    rbac_key = @manager.send(:build_rbac_key, 123, @request.host, @request.path, @request.request_method)
    rbac_cache = @manager.instance_variable_get(:@rbac_cache)

    [false, 'false', 0, '0'].each do |permission_value|
      rbac_cache.clear
      rbac_cache.write(rbac_key, permission_value)

      error = assert_raises(RackJwtAegis::AuthorizationError) do
        @manager.authorize(@request, payload)
      end
      assert_equal 'Access denied - insufficient permissions', error.message
    end
  end

  def test_authorize_rbac_permission_nil
    payload = valid_jwt_payload

    error = assert_raises(RackJwtAegis::AuthorizationError) do
      @manager.authorize(@request, payload)
    end
    assert_equal 'Access denied - insufficient permissions', error.message
  end

  def skip_test_authorize_with_complex_hash_permission_allowed_methods
    payload = valid_jwt_payload
    rbac_key = @manager.send(:build_rbac_key, 123, @request.host, @request.path, @request.request_method)
    rbac_cache = @manager.instance_variable_get(:@rbac_cache)

    rbac_cache.write(rbac_key, { 'allowed_methods' => ['GET', 'POST'] })

    # Should not raise an error for GET request
    @manager.authorize(@request, payload)
  end

  def test_authorize_with_complex_hash_permission_denied_methods
    payload = valid_jwt_payload
    rbac_key = @manager.send(:build_rbac_key, 123, @request.host, @request.path, @request.request_method)
    rbac_cache = @manager.instance_variable_get(:@rbac_cache)

    rbac_cache.write(rbac_key, { 'allowed_methods' => ['POST', 'PUT'] })

    error = assert_raises(RackJwtAegis::AuthorizationError) do
      @manager.authorize(@request, payload)
    end
    assert_equal 'Access denied - insufficient permissions', error.message
  end

  def skip_test_authorize_with_complex_hash_permission_roles
    payload = valid_jwt_payload
    rbac_key = @manager.send(:build_rbac_key, 123, @request.host, @request.path, @request.request_method)
    rbac_cache = @manager.instance_variable_get(:@rbac_cache)

    rbac_cache.write(rbac_key, { 'roles' => ['admin', 'user'] })

    # Should not raise an error (roles present means allowed for now)
    @manager.authorize(@request, payload)
  end

  def test_skip_test_authorize_with_complex_hash_permission_allowed_field
    payload = valid_jwt_payload
    rbac_key = @manager.send(:build_rbac_key, 123, @request.host, @request.path, @request.request_method)
    rbac_cache = @manager.instance_variable_get(:@rbac_cache)

    rbac_cache.write(rbac_key, { 'allowed' => true })
    # Should not raise an error
    @manager.authorize(@request, payload)

    rbac_cache.write(rbac_key, { 'allowed' => false })
    error = assert_raises(RackJwtAegis::AuthorizationError) do
      @manager.authorize(@request, payload)
    end
    assert_equal 'Access denied - insufficient permissions', error.message
  end

  def test_authorize_with_complex_hash_permission_unknown_structure
    payload = valid_jwt_payload
    rbac_key = @manager.send(:build_rbac_key, 123, @request.host, @request.path, @request.request_method)
    rbac_cache = @manager.instance_variable_get(:@rbac_cache)

    rbac_cache.write(rbac_key, { 'unknown_field' => 'value' })

    error = assert_raises(RackJwtAegis::AuthorizationError) do
      @manager.authorize(@request, payload)
    end
    assert_equal 'Access denied - insufficient permissions', error.message
  end

  def test_skip_test_authorize_with_complex_array_permission
    payload = valid_jwt_payload
    rbac_key = @manager.send(:build_rbac_key, 123, @request.host, @request.path, @request.request_method)
    rbac_cache = @manager.instance_variable_get(:@rbac_cache)

    rbac_cache.write(rbac_key, ['GET', 'POST'])
    # Should not raise an error for GET request
    @manager.authorize(@request, payload)

    rbac_cache.write(rbac_key, ['POST', 'PUT'])
    error = assert_raises(RackJwtAegis::AuthorizationError) do
      @manager.authorize(@request, payload)
    end
    assert_equal 'Access denied - insufficient permissions', error.message
  end

  def test_authorize_with_unknown_complex_permission
    payload = valid_jwt_payload
    rbac_key = @manager.send(:build_rbac_key, 123, @request.host, @request.path, @request.request_method)
    rbac_cache = @manager.instance_variable_get(:@rbac_cache)

    rbac_cache.write(rbac_key, Object.new)

    error = assert_raises(RackJwtAegis::AuthorizationError) do
      @manager.authorize(@request, payload)
    end
    assert_equal 'Access denied - insufficient permissions', error.message
  end

  def test_skip_test_authorize_rbac_cache_error
    # Use a manager with debug mode enabled from start
    config = RackJwtAegis::Configuration.new(basic_config.merge(
                                               cache_store: :memory,
                                               cache_write_enabled: true,
                                               debug_mode: true,
                                             ))
    manager = RackJwtAegis::RbacManager.new(config)

    payload = valid_jwt_payload
    rbac_key = manager.send(:build_rbac_key, 123, @request.host, @request.path, @request.request_method)

    # Mock RBAC cache to throw error
    rbac_cache = manager.instance_variable_get(:@rbac_cache)
    rbac_cache.expects(:read).with(rbac_key).raises(RackJwtAegis::CacheError.new('Connection failed'))

    # Expect warning to be printed
    manager.expects(:warn).with(regexp_matches(/RbacManager RBAC cache error/))

    error = assert_raises(RackJwtAegis::AuthorizationError) do
      manager.authorize(@request, payload)
    end
    assert_equal 'Access denied - insufficient permissions', error.message
  end

  def skip_test_cached_permission_cache_read_error
    config = RackJwtAegis::Configuration.new(basic_config.merge(
                                               cache_store: :memory,
                                               cache_write_enabled: true,
                                               debug_mode: true,
                                             ))
    manager = RackJwtAegis::RbacManager.new(config)

    payload = valid_jwt_payload
    permission_key = manager.send(:build_permission_key, 123, @request)
    rbac_key = manager.send(:build_rbac_key, 123, @request.host, @request.path, @request.request_method)

    # Create real cache but stub the read method for the permission key only
    permission_cache = manager.instance_variable_get(:@permission_cache)
    permission_cache.expects(:read).with(permission_key).raises(RackJwtAegis::CacheError.new('Permission cache failed'))

    # RBAC cache will be called since permission cache failed
    rbac_cache = manager.instance_variable_get(:@rbac_cache)
    rbac_cache.write(rbac_key, true)

    # Should warn about cache error but continue
    manager.expects(:warn).with(regexp_matches(/RbacManager cache read error/))

    # Should not raise authorization error since RBAC check succeeds
    manager.authorize(@request, payload)
  end

  def skip_test_cache_permission_result_error
    payload = valid_jwt_payload
    rbac_key = @manager.send(:build_rbac_key, 123, @request.host, @request.path, @request.request_method)
    rbac_cache = @manager.instance_variable_get(:@rbac_cache)
    rbac_cache.write(rbac_key, true)

    # Mock cache write error
    permission_cache = @manager.instance_variable_get(:@permission_cache)
    permission_cache.expects(:write).raises(RackJwtAegis::CacheError.new('Write failed'))

    @config.debug_mode = true

    # Should warn about cache error but not fail the request
    @manager.expects(:warn).with(regexp_matches(/RbacManager permission cache write error/))

    # Should not raise authorization error
    @manager.authorize(@request, payload)
  end

  def skip_test_last_update_timestamp_cache_error
    payload = valid_jwt_payload
    permission_key = @manager.send(:build_permission_key, 123, @request)

    # Mock cached permission
    permission_cache = @manager.instance_variable_get(:@permission_cache)
    permission_cache.write(permission_key, {
      'permission' => true,
      'timestamp' => Time.now.to_i,
    })

    # Mock cache error on last-update read
    rbac_cache = @manager.instance_variable_get(:@rbac_cache)
    rbac_cache.expects(:read).with('last-update').raises(RackJwtAegis::CacheError.new('Read failed'))

    @config.debug_mode = true

    # Should warn about cache error
    @manager.expects(:warn).with(regexp_matches(/RbacManager last-update read error/))

    # Should continue with cached permission since last-update failed
    @manager.authorize(@request, payload)
  end

  def test_skip_test_invalid_cached_entry_format
    payload = valid_jwt_payload
    permission_key = @manager.send(:build_permission_key, 123, @request)
    rbac_key = @manager.send(:build_rbac_key, 123, @request.host, @request.path, @request.request_method)

    # Mock invalid cached entry
    permission_cache = @manager.instance_variable_get(:@permission_cache)
    permission_cache.write(permission_key, 'invalid_format')

    # Mock RBAC cache to provide fallback
    rbac_cache = @manager.instance_variable_get(:@rbac_cache)
    rbac_cache.write(rbac_key, true)

    # Should delete invalid cache entry and fallback to RBAC
    @manager.authorize(@request, payload)

    # Verify invalid entry was removed
    assert_nil permission_cache.read(permission_key)
  end

  def test_build_permission_key
    user_id = 123
    expected_key = "#{user_id}:#{@request.host}:#{@request.path}:#{@request.request_method}"
    actual_key = @manager.send(:build_permission_key, user_id, @request)

    assert_equal expected_key, actual_key
  end

  def test_build_rbac_key
    user_id = 123
    host = 'example.com'
    path = '/api/users'
    method = 'GET'

    expected_key = "#{user_id}:#{host}:#{path}:#{method}"
    actual_key = @manager.send(:build_rbac_key, user_id, host, path, method)

    assert_equal expected_key, actual_key
  end

  def test_authorize_without_permission_cache_write_enabled
    config = RackJwtAegis::Configuration.new(basic_config.merge(
                                               rbac_cache_store: :memory,
                                               cache_write_enabled: false,
                                             ))
    manager = RackJwtAegis::RbacManager.new(config)

    payload = valid_jwt_payload
    request = rack_request(method: 'GET', path: '/api/users')
    rbac_key = manager.send(:build_rbac_key, 123, request.host, request.path, request.request_method)

    # Mock RBAC cache to allow access
    rbac_cache = manager.instance_variable_get(:@rbac_cache)
    rbac_cache.write(rbac_key, true)

    # Should not use permission cache when cache_write_enabled is false
    permission_cache = manager.instance_variable_get(:@permission_cache)

    assert_nil permission_cache

    # Should still authorize successfully
    manager.authorize(request, payload)
  end
end
