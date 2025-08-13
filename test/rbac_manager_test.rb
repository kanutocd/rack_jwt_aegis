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
    current_time = Time.now.to_i

    # Mock cached permission in new format
    permission_cache = @manager.instance_variable_get(:@permission_cache)
    user_permissions = { permission_key => current_time }
    permission_cache.write('user_permissions', user_permissions)

    # Mock last update timestamp - much older than cached permission and outside default TTL (1800s)
    rbac_cache = @manager.instance_variable_get(:@rbac_cache)
    rbac_cache.write('last-update', current_time - 2000) # Older than default TTL (1800s)

    # Should not raise an error
    @manager.authorize(@request, payload)
  end

  def test_build_permission_key
    user_id = 123
    expected_key = "#{user_id}:#{@request.host}#{@request.path}:#{@request.request_method.downcase}"
    actual_key = @manager.send(:build_permission_key, user_id, @request)

    assert_equal expected_key, actual_key
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

    # Mock permission cache to return empty (no cached permission)
    permission_cache = manager.instance_variable_get(:@permission_cache)
    permission_cache.expects(:read).with('user_permissions').returns({})

    # Mock RBAC cache to throw error when checking permissions (called twice - once in get_rbac_last_update_timestamp, once in check_rbac_permission)
    rbac_cache = manager.instance_variable_get(:@rbac_cache)
    rbac_cache.expects(:read).with('permissions').raises(RackJwtAegis::CacheError.new('Connection failed')).twice

    # Expect warnings to be printed for both RBAC cache errors
    manager.expects(:warn).with(regexp_matches(/RbacManager/)).twice

    error = assert_raises(RackJwtAegis::AuthorizationError) do
      manager.authorize(@request, payload)
    end
    assert_equal 'Access denied - insufficient permissions', error.message
  end

  def test_skip_test_invalid_cached_entry_format
    payload = valid_jwt_payload
    permission_key = @manager.send(:build_permission_key, 123, @request)

    # Mock invalid cached entry in user_permissions
    permission_cache = @manager.instance_variable_get(:@permission_cache)
    user_permissions = { permission_key => 'invalid_format' } # Should be integer timestamp
    permission_cache.write('user_permissions', user_permissions)

    # Mock RBAC cache to provide fallback - using new format
    rbac_cache = @manager.instance_variable_get(:@rbac_cache)
    rbac_data = {
      'last_update' => Time.now.to_i,
      'permissions' => [
        { '123' => ['users:get'] },
      ],
    }
    rbac_cache.write('permissions', rbac_data)

    # Set user roles for new format
    @request.env['rack_jwt_aegis.user_roles'] = ['123']

    # Should ignore invalid cache entry and fallback to RBAC
    @manager.authorize(@request, payload)

    # Verify cache was updated with valid entry
    updated_permissions = permission_cache.read('user_permissions')
    cached_timestamp = updated_permissions[permission_key]

    assert_kind_of Integer, cached_timestamp, 'Invalid entry should be replaced with valid timestamp'
  end
end
