# frozen_string_literal: true

require 'test_helper'

class RbacRoleExtractionTest < Minitest::Test
  def setup
    @config = RackJwtAegis::Configuration.new(
      jwt_secret: 'test-secret',
      rbac_enabled: true,
      rbac_cache_store: :memory,
    )
    @middleware = RackJwtAegis::Middleware.new(nil, @config.instance_variables.each_with_object({}) do |var, hash|
      hash[var.to_s.delete('@').to_sym] = @config.instance_variable_get(var)
    end)
  end

  def test_extract_user_roles_with_default_payload_mapping
    payload = { 'role_ids' => ['admin', 'user'] }
    roles = @middleware.send(:extract_user_roles, payload)

    assert_equal ['admin', 'user'], roles
  end

  def test_extract_user_roles_with_custom_payload_mapping
    config = RackJwtAegis::Configuration.new(
      jwt_secret: 'test-secret',
      payload_mapping: { role_ids: :user_roles },
    )
    middleware = RackJwtAegis::Middleware.new(nil, config.instance_variables.each_with_object({}) do |var, hash|
      hash[var.to_s.delete('@').to_sym] = config.instance_variable_get(var)
    end)

    payload = { 'user_roles' => ['manager', 'viewer'] }
    roles = middleware.send(:extract_user_roles, payload)

    assert_equal ['manager', 'viewer'], roles
  end

  def test_extract_user_roles_with_fallback_fields
    payload = { 'roles' => ['admin'] }
    roles = @middleware.send(:extract_user_roles, payload)

    assert_equal ['admin'], roles

    payload = { 'role' => 'user' }
    roles = @middleware.send(:extract_user_roles, payload)

    assert_equal ['user'], roles
  end

  def test_extract_user_roles_with_integer_role
    payload = { 'role_ids' => [1, 2] }
    roles = @middleware.send(:extract_user_roles, payload)

    assert_equal ['1', '2'], roles
  end

  def test_extract_user_roles_with_single_string_role
    payload = { 'role_ids' => 'admin' }
    roles = @middleware.send(:extract_user_roles, payload)

    assert_equal ['admin'], roles
  end

  def test_extract_user_roles_returns_empty_for_invalid_data
    payload = { 'role_ids' => nil }
    roles = @middleware.send(:extract_user_roles, payload)

    assert_empty roles

    payload = {}
    roles = @middleware.send(:extract_user_roles, payload)

    assert_empty roles
  end
end
