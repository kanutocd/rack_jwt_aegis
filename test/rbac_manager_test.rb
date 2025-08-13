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

  def test_cache_write_disabled_mode
    # Test mode where cache_write_enabled is false
    config = RackJwtAegis::Configuration.new(
      jwt_secret: 'secret',
      rbac_cache_store: :memory,
      permission_cache_store: :memory,
      cache_write_enabled: false
    )
    manager = RackJwtAegis::RbacManager.new(config)

    payload = valid_jwt_payload
    @request.env['rack_jwt_aegis.user_roles'] = ['123']

    # Setup RBAC data
    rbac_cache = manager.instance_variable_get(:@rbac_cache)
    rbac_data = {
      'last_update' => Time.now.to_i,
      'permissions' => [
        { '123' => ['users:get'] },
      ],
    }
    rbac_cache.write('permissions', rbac_data)

    # Should authorize but not cache the result
    manager.authorize(@request, payload)

    # Verify permission was not cached since cache_write_enabled is false
    permission_cache = manager.instance_variable_get(:@permission_cache)
    user_permissions = permission_cache.read('user_permissions')
    
    assert_nil user_permissions
  end

  def test_rbac_format_validation_edge_cases
    # Test various invalid RBAC formats
    manager = @manager

    # Test with non-hash input
    refute manager.send(:validate_rbac_cache_format, 'not-a-hash')
    refute manager.send(:validate_rbac_cache_format, [])
    refute manager.send(:validate_rbac_cache_format, nil)

    # Test missing required fields
    refute manager.send(:validate_rbac_cache_format, {})
    refute manager.send(:validate_rbac_cache_format, { 'last_update' => 123 })
    refute manager.send(:validate_rbac_cache_format, { 'permissions' => [] })

    # Test invalid permissions structure
    refute manager.send(:validate_rbac_cache_format, {
      'last_update' => 123,
      'permissions' => 'not-an-array'
    })

    # Test empty permissions array is valid
    assert manager.send(:validate_rbac_cache_format, {
      'last_update' => 123,
      'permissions' => []
    })

    # Test invalid permission entry (not a hash)
    refute manager.send(:validate_rbac_cache_format, {
      'last_update' => 123,
      'permissions' => ['not-a-hash']
    })

    # Test empty permission entry (should be invalid)
    refute manager.send(:validate_rbac_cache_format, {
      'last_update' => 123,
      'permissions' => [{}]
    })

    # Test invalid permission values (not array)
    refute manager.send(:validate_rbac_cache_format, {
      'last_update' => 123,
      'permissions' => [{ '123' => 'not-an-array' }]
    })

    # Test invalid permission format (missing colon)
    refute manager.send(:validate_rbac_cache_format, {
      'last_update' => 123,
      'permissions' => [{ '123' => ['invalid-permission-format'] }]
    })

    # Test invalid permission format (not string)
    refute manager.send(:validate_rbac_cache_format, {
      'last_update' => 123,
      'permissions' => [{ '123' => [123] }]
    })

    # Test valid format with symbol keys
    assert manager.send(:validate_rbac_cache_format, {
      last_update: 123,
      permissions: [{ '123' => ['users:get'] }]
    })
  end

  def test_cache_permission_result_only_caches_positive_permissions
    permission_key = @manager.send(:build_permission_key, 123, @request)

    # Test that negative permissions are not cached
    @manager.send(:cache_permission_result, permission_key, false)

    permission_cache = @manager.instance_variable_get(:@permission_cache)
    user_permissions = permission_cache.read('user_permissions')
    
    # Should be empty or nil since false permissions are not cached
    assert user_permissions.nil? || user_permissions.empty?

    # Test that positive permissions are cached
    @manager.send(:cache_permission_result, permission_key, true)

    user_permissions = permission_cache.read('user_permissions')
    assert_kind_of Hash, user_permissions
    assert_kind_of Integer, user_permissions[permission_key]
  end

  def test_remove_stale_permission_edge_cases
    permission_cache = @manager.instance_variable_get(:@permission_cache)
    
    # Test removing from non-existent cache
    @manager.send(:remove_stale_permission, 'nonexistent:key', 'test reason')
    
    # Test removing last permission clears entire cache
    permission_key = 'test:key'
    user_permissions = { permission_key => Time.now.to_i }
    permission_cache.write('user_permissions', user_permissions)
    
    @manager.send(:remove_stale_permission, permission_key, 'last permission')
    
    # Cache should be deleted entirely
    assert_nil permission_cache.read('user_permissions')
  end

  def test_permission_matches_edge_cases
    manager = @manager

    # Test invalid permission format
    refute manager.send(:permission_matches?, 'invalid-format', 'users', 'get')
    refute manager.send(:permission_matches?, nil, 'users', 'get')
    refute manager.send(:permission_matches?, 123, 'users', 'get')

    # Test permission with wrong number of parts
    refute manager.send(:permission_matches?, 'users', 'users', 'get')
    refute manager.send(:permission_matches?, 'users:get:extra', 'users', 'get')

    # Test wildcard method matching
    assert manager.send(:permission_matches?, 'users:*', 'users', 'get')
    assert manager.send(:permission_matches?, 'users:*', 'users', 'post')
    assert manager.send(:permission_matches?, 'users:*', 'users', 'delete')

    # Test case insensitive method matching  
    assert manager.send(:permission_matches?, 'users:GET', 'users', 'get')
    assert manager.send(:permission_matches?, 'users:get', 'users', 'get')  # Fixed - both should be lowercase for request_method
  end

  def test_regex_permission_error_handling
    config_with_debug = RackJwtAegis::Configuration.new(basic_config.merge(
      cache_store: :memory,
      cache_write_enabled: true,
      debug_mode: true
    ))
    manager = RackJwtAegis::RbacManager.new(config_with_debug)

    # Test invalid regex pattern that will definitely cause a RegexpError
    invalid_regex_permission = '%r{*+}'  # Invalid regex quantifier
    
    # Capture the warnings using stderr since that's where warn goes
    warning_output = capture_warnings do
      result = manager.send(:path_matches?, invalid_regex_permission, 'test/path')
      refute result, 'Invalid regex should not match'
    end
    
    assert_match(/Invalid regex pattern/, warning_output)
  end

  def test_validate_rbac_cache_format_with_exception
    config_with_debug = RackJwtAegis::Configuration.new(basic_config.merge(
      cache_store: :memory,
      cache_write_enabled: true,
      debug_mode: true
    ))
    manager = RackJwtAegis::RbacManager.new(config_with_debug)

    # Create a malformed object that will cause an exception during validation
    # Instead of stubbing is_a?, let's stub a method that's actually called in the validation
    malformed_data = { 'last_update' => 123, 'permissions' => [] }
    malformed_data.stubs(:key?).raises(StandardError.new('Validation error'))

    # Should capture the warning and return false
    warning_output = capture_warnings do
      result = manager.send(:validate_rbac_cache_format, malformed_data)
      refute result, 'Should return false when validation throws exception'
    end

    assert_match(/Cache format validation error/, warning_output)
  end

  def test_no_user_roles_in_request_context
    config_with_debug = RackJwtAegis::Configuration.new(basic_config.merge(
      cache_store: :memory,
      cache_write_enabled: true,
      debug_mode: true
    ))
    manager = RackJwtAegis::RbacManager.new(config_with_debug)

    payload = valid_jwt_payload
    @request.env['rack_jwt_aegis.user_roles'] = nil  # No roles

    # Setup RBAC data
    rbac_cache = manager.instance_variable_get(:@rbac_cache)
    rbac_data = {
      'last_update' => Time.now.to_i,
      'permissions' => [
        { '123' => ['users:get'] },
      ],
    }
    rbac_cache.write('permissions', rbac_data)

    # Should capture warning about missing roles
    warning_output = capture_warnings do
      error = assert_raises(RackJwtAegis::AuthorizationError) do
        manager.authorize(@request, payload)
      end
      assert_equal 'Access denied - insufficient permissions', error.message
    end

    assert_match(/No user roles found in request context/, warning_output)
  end

  def test_check_rbac_permission_with_invalid_data
    @request.env['rack_jwt_aegis.user_roles'] = ['123']

    # Setup invalid RBAC data (not a hash)
    rbac_cache = @manager.instance_variable_get(:@rbac_cache)
    rbac_cache.write('permissions', 'invalid-data')

    # Should fallback to false when RBAC data is invalid
    result = @manager.send(:check_rbac_permission, 123, @request)
    refute result
  end

  def test_cache_permission_match_with_nil_host
    @request.stubs(:host).returns(nil)
    @request.stubs(:path).returns('/test/path')
    @request.stubs(:request_method).returns('GET')

    # Should handle nil host gracefully
    @manager.send(:cache_permission_match, 123, @request, '456', 'test:get')

    permission_cache = @manager.instance_variable_get(:@permission_cache)
    user_permissions = permission_cache.read('user_permissions')
    
    # Should cache with 'localhost' as default host
    expected_key = '123:localhost/test/path:get'
    assert_kind_of Hash, user_permissions
    assert user_permissions.key?(expected_key)
  end

  def test_extract_api_path_from_request_edge_cases
    manager = @manager

    # Test with pathname slug pattern configured
    request_with_slug = rack_request(method: 'GET', path: '/api/v1/company-name/users/123')
    extracted = manager.send(:extract_api_path_from_request, request_with_slug)
    assert_equal 'users/123', extracted

    # Test path that doesn't match slug pattern
    request_no_slug = rack_request(method: 'GET', path: '/api/v2/direct/users')
    extracted = manager.send(:extract_api_path_from_request, request_no_slug)
    assert_equal 'direct/users', extracted

    # Test path with just /api/ prefix
    request_api = rack_request(method: 'GET', path: '/api/users')
    extracted = manager.send(:extract_api_path_from_request, request_api)
    assert_equal 'users', extracted

    # Test root path
    request_root = rack_request(method: 'GET', path: '/')
    extracted = manager.send(:extract_api_path_from_request, request_root)
    assert_equal '', extracted
  end

  def test_get_rbac_last_update_timestamp_edge_cases
    # Test with nil rbac_cache by setting it manually
    original_cache = @manager.instance_variable_get(:@rbac_cache)
    @manager.instance_variable_set(:@rbac_cache, nil)

    result = @manager.send(:get_rbac_last_update_timestamp)
    assert_nil result

    # Restore the original cache
    @manager.instance_variable_set(:@rbac_cache, original_cache)
    rbac_cache = @manager.instance_variable_get(:@rbac_cache)

    # Test with missing last_update field
    rbac_cache.write('permissions', { 'permissions' => [] })

    result = @manager.send(:get_rbac_last_update_timestamp)
    assert_nil result

    # Test with non-hash data
    rbac_cache.write('permissions', 'not-a-hash')

    result = @manager.send(:get_rbac_last_update_timestamp)
    assert_nil result
  end

  def test_remove_stale_permission_with_cache_error
    config_with_debug = RackJwtAegis::Configuration.new(basic_config.merge(
      cache_store: :memory,
      cache_write_enabled: true,
      debug_mode: true
    ))
    manager = RackJwtAegis::RbacManager.new(config_with_debug)

    # Mock permission cache to throw error on read
    permission_cache = manager.instance_variable_get(:@permission_cache)
    permission_cache.stubs(:read).raises(RackJwtAegis::CacheError.new('Read failed'))

    # Should capture warning and not raise exception
    warning_output = capture_warnings do
      manager.send(:remove_stale_permission, 'test:key', 'test reason')
    end

    assert_match(/stale permission removal error/, warning_output)
  end

  def test_check_rbac_format_with_role_id_as_integer
    @request.env['rack_jwt_aegis.user_roles'] = [123]  # Integer role ID

    # Setup RBAC data with integer role keys
    rbac_data = {
      'last_update' => Time.now.to_i,
      'permissions' => [
        { 123 => ['users:get'] },  # Integer key instead of string
      ],
    }

    result = @manager.send(:check_rbac_format, 123, @request, rbac_data)
    assert result
  end

  def test_extract_api_path_with_pattern_no_match
    # Test when pattern doesn't match
    request_no_match = rack_request(method: 'GET', path: '/different/path/structure')
    
    # Should fall back to removing /api/v1/ prefix
    extracted = @manager.send(:extract_api_path_from_request, request_no_match)
    assert_equal 'different/path/structure', extracted
  end

  def test_extract_api_path_with_pattern_no_captures
    # Test when pattern matches but has no captures
    config_no_captures = RackJwtAegis::Configuration.new(basic_config.merge(
      cache_store: :memory,
      cache_write_enabled: true,
      pathname_slug_pattern: /\/api\/v1\//  # No capture groups
    ))
    manager = RackJwtAegis::RbacManager.new(config_no_captures)
    
    request = rack_request(method: 'GET', path: '/api/v1/users')
    extracted = manager.send(:extract_api_path_from_request, request)
    
    # Should fall back to removing prefixes
    assert_equal 'users', extracted
  end

  def test_nuke_user_permissions_cache_with_cache_error
    config_with_debug = RackJwtAegis::Configuration.new(basic_config.merge(
      cache_store: :memory,
      cache_write_enabled: true,
      debug_mode: true
    ))
    manager = RackJwtAegis::RbacManager.new(config_with_debug)

    # Mock permission cache to throw error on delete
    permission_cache = manager.instance_variable_get(:@permission_cache)
    permission_cache.stubs(:delete).raises(RackJwtAegis::CacheError.new('Delete failed'))

    # Should capture warning and not raise exception
    warning_output = capture_warnings do
      manager.send(:nuke_user_permissions_cache, 'test reason')
    end

    assert_match(/cache nuke error/, warning_output)
  end

  def test_cache_permission_result_with_cache_error
    config_with_debug = RackJwtAegis::Configuration.new(basic_config.merge(
      cache_store: :memory,
      cache_write_enabled: true,
      debug_mode: true
    ))
    manager = RackJwtAegis::RbacManager.new(config_with_debug)

    # Mock permission cache to throw error on write
    permission_cache = manager.instance_variable_get(:@permission_cache)
    permission_cache.stubs(:write).raises(RackJwtAegis::CacheError.new('Write failed'))

    # Should capture warning and not raise exception
    warning_output = capture_warnings do
      manager.send(:cache_permission_result, 'test:key', true)
    end

    assert_match(/permission cache write error/, warning_output)
  end

  private

  def capture_warnings
    original_stderr = $stderr
    captured_output = StringIO.new
    $stderr = captured_output
    
    yield
    
    captured_output.string
  ensure
    $stderr = original_stderr
  end

  def capture_stdout
    original_stdout = $stdout
    captured_output = StringIO.new
    $stdout = captured_output
    
    yield
    
    captured_output.string
  ensure
    $stdout = original_stdout
  end
end
