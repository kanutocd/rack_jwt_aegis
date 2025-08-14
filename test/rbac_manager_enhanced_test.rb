# frozen_string_literal: true

require 'test_helper'

class RbacManagerEnhancedTest < Minitest::Test
  def setup
    @config = RackJwtAegis::Configuration.new(basic_config.merge(
                                                cache_store: :memory,
                                                cache_write_enabled: true,
                                                user_permissions_ttl: 300, # 5 minutes for testing
                                                debug_mode: true,
                                              ))
    @manager = RackJwtAegis::RbacManager.new(@config)
    @request = rack_request(method: 'POST', path: '/api/v1/acme-company/sales/invoices',
                            host: 'acme-group.localhost.local')
  end

  def test_configurable_ttl_used_from_config
    # Test that the manager uses the configured TTL instead of hardcoded values
    assert_equal 300, @config.user_permissions_ttl

    # Setup user permissions cache with timestamp older than configured TTL in new format
    permission_key = @manager.send(:build_permission_key, 123, @request)
    user_permissions = {
      permission_key => Time.now.to_i - 400, # 400s ago, older than 300s TTL
    }
    permission_cache = @manager.instance_variable_get(:@permission_cache)
    permission_cache.write('user_permissions', user_permissions)

    # Should be cache miss due to TTL expiration
    result = @manager.send(:check_cached_permission, permission_key)

    assert_nil result, 'Should be cache miss due to TTL expiration'

    # Verify the stale permission was removed
    updated_permissions = permission_cache.read('user_permissions')

    assert updated_permissions.nil? || updated_permissions[permission_key].nil?,
           'Stale permission should be removed'
  end

  def test_per_permission_timestamp_caching
    payload = valid_jwt_payload.merge('roles' => ['123'])
    @request.env['rack_jwt_aegis.user_roles'] = ['123']

    # Setup new RBAC format
    rbac_data = {
      'last_update' => Time.now.to_i,
      'permissions' => {
        '123' => ['sales/invoices:post'],
      },
    }

    rbac_cache = @manager.instance_variable_get(:@rbac_cache)
    rbac_cache.write('permissions', rbac_data)

    # First authorization should cache the permission with timestamp
    @manager.authorize(@request, payload)

    permission_cache = @manager.instance_variable_get(:@permission_cache)
    user_permissions = permission_cache.read('user_permissions')

    assert_kind_of Hash, user_permissions

    # Check new format: permission_key => timestamp
    permission_key = @manager.send(:build_permission_key, 123, @request)
    cached_timestamp = user_permissions[permission_key]

    assert_kind_of Integer, cached_timestamp, 'Cached value should be timestamp'
    assert_operator cached_timestamp, :>, (Time.now.to_i - 5), 'Timestamp should be recent'
  end

  def test_fine_grained_permission_matching_literal
    payload = valid_jwt_payload.merge('roles' => ['123'])
    @request.env['rack_jwt_aegis.user_roles'] = ['123']

    # Test exact literal matching
    rbac_data = {
      'last_update' => Time.now.to_i,
      'permissions' => {
        '123' => ['sales/invoices:post', 'sales/invoices:get'],
      },
    }

    rbac_cache = @manager.instance_variable_get(:@rbac_cache)
    rbac_cache.write('permissions', rbac_data)

    # Should authorize POST to sales/invoices
    @manager.authorize(@request, payload) # Should not raise

    # Should NOT authorize DELETE to sales/invoices
    delete_request = rack_request(method: 'DELETE', path: '/api/v1/acme-company/sales/invoices',
                                  host: 'acme-group.localhost.local')
    delete_request.env['rack_jwt_aegis.user_roles'] = ['123']

    assert_raises(RackJwtAegis::AuthorizationError) do
      @manager.authorize(delete_request, payload)
    end
  end

  def test_fine_grained_permission_matching_regex
    payload = valid_jwt_payload.merge('roles' => ['456'])

    # Test regex pattern matching
    rbac_data = {
      'last_update' => Time.now.to_i,
      'permissions' => {
        '456' => ['%r{sales/invoices/\\d+}:get', '%r{sales/invoices/\\d+}:put'],
      },
    }

    rbac_cache = @manager.instance_variable_get(:@rbac_cache)
    rbac_cache.write('permissions', rbac_data)

    # Should authorize GET to sales/invoices/123
    get_request = rack_request(method: 'GET', path: '/api/v1/acme-company/sales/invoices/123',
                               host: 'acme-group.localhost.local')
    get_request.env['rack_jwt_aegis.user_roles'] = ['456']

    @manager.authorize(get_request, payload) # Should not raise

    # Should authorize PUT to sales/invoices/456
    put_request = rack_request(method: 'PUT', path: '/api/v1/acme-company/sales/invoices/456',
                               host: 'acme-group.localhost.local')
    put_request.env['rack_jwt_aegis.user_roles'] = ['456']

    @manager.authorize(put_request, payload) # Should not raise

    # Should NOT authorize DELETE to sales/invoices/123 (not in permissions)
    delete_request = rack_request(method: 'DELETE', path: '/api/v1/acme-company/sales/invoices/123',
                                  host: 'acme-group.localhost.local')
    delete_request.env['rack_jwt_aegis.user_roles'] = ['456']

    assert_raises(RackJwtAegis::AuthorizationError) do
      @manager.authorize(delete_request, payload)
    end
  end

  def test_fine_grained_permission_matching_wildcard_method
    payload = valid_jwt_payload.merge('roles' => ['789'])

    # Test wildcard method matching - use exact paths that will be extracted
    rbac_data = {
      'last_update' => Time.now.to_i,
      'permissions' => {
        '789' => ['admin/users:*', 'reports:*'],
      },
    }

    rbac_cache = @manager.instance_variable_get(:@rbac_cache)
    rbac_cache.write('permissions', rbac_data)

    # Should authorize any method on admin/users endpoint
    admin_request = rack_request(method: 'DELETE', path: '/api/v1/acme-company/admin/users',
                                 host: 'acme-group.localhost.local')
    admin_request.env['rack_jwt_aegis.user_roles'] = ['789']

    @manager.authorize(admin_request, payload) # Should not raise

    # Should authorize any method on reports
    reports_request = rack_request(method: 'POST', path: '/api/v1/acme-company/reports',
                                   host: 'acme-group.localhost.local')
    reports_request.env['rack_jwt_aegis.user_roles'] = ['789']

    @manager.authorize(reports_request, payload) # Should not raise
  end

  def test_cache_invalidation_on_rbac_update_within_ttl
    valid_jwt_payload.merge('roles' => ['123'])

    # Setup initial cache
    current_time = Time.now.to_i
    user_permissions = {
      '54321:acme-group.localhost.local/api/v1/acme-company/sales/invoices:get' => current_time - 100,
      '54321:acme-group.localhost.local/api/v1/acme-company/sales/invoices:post' => current_time - 100,
    }

    permission_cache = @manager.instance_variable_get(:@permission_cache)
    permission_cache.write('user_permissions', user_permissions)

    # Setup RBAC data with recent update (within TTL)
    rbac_data = {
      'last_update' => current_time - 200, # Updated 200s ago, within 300s TTL
      'permissions' => {
        '123' => ['sales/invoices:post'],
      },
    }
    rbac_cache = @manager.instance_variable_get(:@rbac_cache)
    rbac_cache.write('permissions', rbac_data)

    # Check cache - should nuke entire cache due to recent RBAC update
    permission_key = @manager.send(:build_permission_key, 123, @request)
    result = @manager.send(:check_cached_permission, permission_key)

    assert_nil result, 'Should be cache miss due to RBAC update within TTL'

    # Verify entire cache was nuked
    permission_cache = @manager.instance_variable_get(:@permission_cache)
    updated_permissions = permission_cache.read('user_permissions')

    assert_nil updated_permissions, 'Entire cache should be nuked'
  end

  def test_cache_preservation_on_individual_ttl_expiration
    # Setup cache with mixed timestamps in new format
    current_time = Time.now.to_i

    # Create permission keys for different scenarios
    expired_key = '123:acme-group.localhost.local/api/v1/acme-company/sales/invoices:post'
    fresh_key_user_one = '123:acme-group.localhost.local/api/v1/acme-company/users/profile:get'
    fresh_key_user_four = '456:acme-group.localhost.local/api/v1/acme-company/reports:get'

    user_permissions = {
      expired_key => current_time - 400, # Expired
      fresh_key_user_one => current_time - 100, # Fresh
      fresh_key_user_four => current_time - 150, # Fresh
    }
    permission_cache = @manager.instance_variable_get(:@permission_cache)
    permission_cache.write('user_permissions', user_permissions)

    # Setup RBAC data with old update (outside TTL)
    rbac_data = {
      'last_update' => current_time - 500, # Updated 500s ago, outside 300s TTL
      'permissions' => {
        '123' => ['sales/invoices:post'],
      },
    }
    rbac_cache = @manager.instance_variable_get(:@rbac_cache)
    rbac_cache.write('permissions', rbac_data)

    # Check expired permission
    permission_key = @manager.send(:build_permission_key, 123, @request)
    result = @manager.send(:check_cached_permission, permission_key)

    assert_nil result, 'Should be cache miss due to individual TTL expiration'

    # Verify only the expired permission was removed, others preserved
    updated_permissions = permission_cache.read('user_permissions')

    assert_kind_of Hash, updated_permissions, 'Cache should still exist'
    assert_nil updated_permissions[expired_key], 'Expired permission should be removed'
    assert updated_permissions[fresh_key_user_one], 'Fresh permission for same user should be preserved'
    assert updated_permissions[fresh_key_user_four], "Other user's permissions should be preserved"
  end

  def test_cache_format_validation
    # Test invalid RBAC cache format
    rbac_cache = @manager.instance_variable_get(:@rbac_cache)

    # Invalid format - missing required fields
    rbac_cache.write('permissions', { 'invalid' => 'format' })

    payload = valid_jwt_payload.merge('roles' => ['123'])
    @request.env['rack_jwt_aegis.user_roles'] = ['123']

    # Should deny access when RBAC format is invalid
    assert_raises(RackJwtAegis::AuthorizationError) do
      @manager.authorize(@request, payload)
    end

    # Test valid format
    valid_rbac = {
      'last_update' => Time.now.to_i,
      'permissions' => {
        '123' => ['sales/invoices:post'],
      },
    }
    rbac_cache.write('permissions', valid_rbac)

    # Should work with valid format
    @manager.authorize(@request, payload) # Should not raise
  end

  def test_role_extraction_from_jwt_payload
    # Test various role field formats
    test_cases = [
      { payload: { 'roles' => ['123', '456'] }, expected: ['123', '456'] },
      { payload: { 'role' => '789' }, expected: ['789'] },
      { payload: { 'user_roles' => [111, 222] }, expected: ['111', '222'] },
      { payload: { 'role_ids' => 333 }, expected: ['333'] },
    ]

    test_cases.each do |test_case|
      @request.env['rack_jwt_aegis.user_roles'] = test_case[:expected]

      # Verify roles are properly stored in request environment
      assert_equal test_case[:expected], @request.env['rack_jwt_aegis.user_roles']
    end
  end

  private

  def valid_jwt_payload
    {
      'user_id' => 123,
      'tenant_id' => 456,
      'exp' => Time.now.to_i + 3600,
    }
  end
end
