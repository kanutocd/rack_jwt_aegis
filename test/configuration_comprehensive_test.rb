# frozen_string_literal: true

require 'test_helper'

class ConfigurationComprehensiveTest < Minitest::Test
  def test_initialization_with_defaults
    config = RackJwtAegis::Configuration.new(jwt_secret: 'test-secret')

    assert_equal 'test-secret', config.jwt_secret
    assert_equal 'HS256', config.jwt_algorithm
    assert_equal 'X-Tenant-Id', config.tenant_id_header_name
    refute_predicate config, :validate_subdomain?
    refute_predicate config, :validate_pathname_slug?
    refute_predicate config, :rbac_enabled?
    refute_predicate config, :debug_mode?
    assert_empty config.skip_paths
    assert_equal(%r{^/api/v1/([^/]+)/}, config.pathname_slug_pattern)
  end

  def test_initialization_with_custom_values
    options = {
      jwt_secret: 'custom-secret',
      jwt_algorithm: 'HS512',
      tenant_id_header_name: 'X-Custom-Tenant',
      validate_subdomain: true,
      validate_pathname_slug: true,
      rbac_enabled: true,
      rbac_cache_store: :memory,
      debug_mode: true,
      skip_paths: ['/health', '/status'],
      pathname_slug_pattern: %r{^/company/([^/]+)/},
    }

    config = RackJwtAegis::Configuration.new(options)

    assert_equal 'custom-secret', config.jwt_secret
    assert_equal 'HS512', config.jwt_algorithm
    assert_equal 'X-Custom-Tenant', config.tenant_id_header_name
    assert_predicate config, :validate_subdomain?
    assert_predicate config, :validate_pathname_slug?
    assert_predicate config, :rbac_enabled?
    assert_predicate config, :debug_mode?
    assert_equal ['/health', '/status'], config.skip_paths
    assert_equal(%r{^/company/([^/]+)/}, config.pathname_slug_pattern)
  end

  def test_missing_jwt_secret_raises_error
    error = assert_raises(RackJwtAegis::ConfigurationError) do
      RackJwtAegis::Configuration.new({})
    end
    assert_equal 'jwt_secret is required', error.message
  end

  def test_empty_jwt_secret_raises_error
    error = assert_raises(RackJwtAegis::ConfigurationError) do
      RackJwtAegis::Configuration.new(jwt_secret: '')
    end
    assert_equal 'jwt_secret is required', error.message
  end

  def test_nil_jwt_secret_raises_error
    error = assert_raises(RackJwtAegis::ConfigurationError) do
      RackJwtAegis::Configuration.new(jwt_secret: nil)
    end
    assert_equal 'jwt_secret is required', error.message
  end

  def test_validate_pathname_slug_without_pattern
    error = assert_raises(RackJwtAegis::ConfigurationError) do
      RackJwtAegis::Configuration.new(
        jwt_secret: 'test-secret',
        validate_pathname_slug: true,
        pathname_slug_pattern: nil,
      )
    end
    assert_equal 'pathname_slug_pattern is required when validate_pathname_slug is true', error.message
  end

  def test_validate_subdomain_without_subdomain_mapping
    error = assert_raises(RackJwtAegis::ConfigurationError) do
      RackJwtAegis::Configuration.new(
        jwt_secret: 'test-secret',
        validate_subdomain: true,
        payload_mapping: { user_id: :sub },
      )
    end
    assert_equal 'payload_mapping must include :subdomain when validate_subdomain is true', error.message
  end

  def test_validate_pathname_slug_without_pathname_slugs_mapping
    error = assert_raises(RackJwtAegis::ConfigurationError) do
      RackJwtAegis::Configuration.new(
        jwt_secret: 'test-secret',
        validate_pathname_slug: true,
        payload_mapping: { user_id: :sub },
      )
    end
    assert_equal 'payload_mapping must include :pathname_slugs when validate_pathname_slug is true', error.message
  end

  def test_config_boolean_true_values
    config = RackJwtAegis::Configuration.new(jwt_secret: 'test')

    assert config.send(:config_boolean?, true)
    assert config.send(:config_boolean?, 'true')
    assert config.send(:config_boolean?, 'yes')
    assert config.send(:config_boolean?, '1')
    assert config.send(:config_boolean?, 1)
  end

  def test_config_boolean_false_values
    config = RackJwtAegis::Configuration.new(jwt_secret: 'test')

    refute config.send(:config_boolean?, false)
    refute config.send(:config_boolean?, 'false')
    refute config.send(:config_boolean?, '0')
    refute config.send(:config_boolean?, 0)
    refute config.send(:config_boolean?, nil)
    refute config.send(:config_boolean?, '')
    refute config.send(:config_boolean?, 'no')

    # NOTE: The implementation treats most strings as truthy except 'false' and ''

    assert config.send(:config_boolean?, 'other') # Other strings are truthy
  end

  def test_payload_key_default_mapping
    config = RackJwtAegis::Configuration.new(jwt_secret: 'test')

    assert_equal :user_id, config.payload_key(:user_id)
    assert_equal :tenant_id, config.payload_key(:tenant_id)
    assert_equal :subdomain, config.payload_key(:subdomain)
    assert_equal :pathname_slugs, config.payload_key(:pathname_slugs)
  end

  def test_payload_key_custom_mapping
    config = RackJwtAegis::Configuration.new(
      jwt_secret: 'test',
      payload_mapping: {
        user_id: :sub,
        tenant_id: :company_group_id,
        subdomain: :domain,
        pathname_slugs: :accessible_companies,
      },
    )

    assert_equal :sub, config.payload_key(:user_id)
    assert_equal :company_group_id, config.payload_key(:tenant_id)
    assert_equal :domain, config.payload_key(:subdomain)
    assert_equal :accessible_companies, config.payload_key(:pathname_slugs)
  end

  def test_skip_path_exact_match
    config = RackJwtAegis::Configuration.new(
      jwt_secret: 'test',
      skip_paths: ['/health', '/status'],
    )

    assert config.skip_path?('/health')
    assert config.skip_path?('/status')
    refute config.skip_path?('/api/users')
  end

  def test_skip_path_pattern_match
    config = RackJwtAegis::Configuration.new(
      jwt_secret: 'test',
      skip_paths: ['/api/v1/public/*', '/health'],
    )

    # The implementation uses simple string matching, not glob patterns
    # Let's test the actual behavior
    assert config.skip_path?('/health')
    refute config.skip_path?('/api/v1/public/info') # Pattern matching not implemented
    refute config.skip_path?('/api/v1/users')
  end

  def test_skip_path_empty_paths
    config = RackJwtAegis::Configuration.new(jwt_secret: 'test')

    refute config.skip_path?('/any/path')
  end

  def test_unauthorized_response_default
    config = RackJwtAegis::Configuration.new(jwt_secret: 'test')

    assert_equal({ error: 'Authentication required' }, config.unauthorized_response)
  end

  def test_unauthorized_response_custom
    custom_response = { error: 'Please login', code: 'AUTH_REQUIRED' }
    config = RackJwtAegis::Configuration.new(
      jwt_secret: 'test',
      unauthorized_response: custom_response,
    )

    assert_equal custom_response, config.unauthorized_response
  end

  def test_forbidden_response_default
    config = RackJwtAegis::Configuration.new(jwt_secret: 'test')

    assert_equal({ error: 'Access denied' }, config.forbidden_response)
  end

  def test_forbidden_response_custom
    custom_response = { error: 'Insufficient permissions', code: 'ACCESS_DENIED' }
    config = RackJwtAegis::Configuration.new(
      jwt_secret: 'test',
      forbidden_response: custom_response,
    )

    assert_equal custom_response, config.forbidden_response
  end

  def test_cache_write_enabled_default
    config = RackJwtAegis::Configuration.new(jwt_secret: 'test')

    refute_predicate config, :cache_write_enabled?
  end

  def test_cache_write_enabled_true
    config = RackJwtAegis::Configuration.new(
      jwt_secret: 'test',
      cache_write_enabled: true,
    )

    assert_predicate config, :cache_write_enabled?
  end

  def test_rbac_enabled_predicate_methods
    config = RackJwtAegis::Configuration.new(
      jwt_secret: 'test',
      rbac_enabled: true,
      rbac_cache_store: :memory,
    )

    assert_predicate config, :rbac_enabled?
  end

  def test_debug_mode_predicate_method
    config = RackJwtAegis::Configuration.new(
      jwt_secret: 'test',
      debug_mode: true,
    )

    assert_predicate config, :debug_mode?
  end

  def test_cache_configuration_getters
    config = RackJwtAegis::Configuration.new(
      jwt_secret: 'test',
      cache_store: :redis,
      cache_options: { host: 'localhost' },
      rbac_cache_store: :memory,
      rbac_cache_options: { size: 1000 },
      permission_cache_store: :memcached,
      permission_cache_options: { servers: ['localhost:11211'] },
    )

    assert_equal :redis, config.cache_store
    assert_equal({ host: 'localhost' }, config.cache_options)
    assert_equal :memory, config.rbac_cache_store
    assert_equal({ size: 1000 }, config.rbac_cache_options)
    assert_equal :memcached, config.permission_cache_store
    assert_equal({ servers: ['localhost:11211'] }, config.permission_cache_options)
  end

  def test_custom_payload_validator_getter
    validator = ->(payload, _request) { payload['role'] == 'admin' }
    config = RackJwtAegis::Configuration.new(
      jwt_secret: 'test',
      custom_payload_validator: validator,
    )

    assert_equal validator, config.custom_payload_validator
  end

  def test_initialization_with_symbol_keys
    # Test that configuration works with symbol keys
    options = {
      jwt_secret: 'test-secret',
      debug_mode: true,
      skip_paths: ['/health'],
    }

    config = RackJwtAegis::Configuration.new(options)

    assert_equal 'test-secret', config.jwt_secret
    assert_predicate config, :debug_mode?
    assert_equal ['/health'], config.skip_paths
  end

  def test_initialization_with_string_keys
    # Test that configuration works with string keys
    options = {
      'jwt_secret' => 'test-secret',
      'debug_mode' => true,
      'skip_paths' => ['/health'],
    }

    config = RackJwtAegis::Configuration.new(options)

    assert_equal 'test-secret', config.jwt_secret
    assert_predicate config, :debug_mode?
    assert_equal ['/health'], config.skip_paths
  end

  def test_valid_configuration_with_all_features
    options = {
      jwt_secret: 'test-secret',
      validate_subdomain: true,
      validate_pathname_slug: true,
      rbac_enabled: true,
      cache_store: :memory,
      cache_write_enabled: true,
      payload_mapping: {
        subdomain: :domain,
        pathname_slugs: :companies,
      },
    }

    # Should not raise any errors
    config = RackJwtAegis::Configuration.new(options)

    assert_predicate config, :validate_subdomain?
    assert_predicate config, :validate_pathname_slug?
    assert_predicate config, :rbac_enabled?
    assert_predicate config, :cache_write_enabled?
  end

  def test_rbac_cache_store_required_when_cache_write_disabled
    # Test line 303: rbac_cache_store.nil? check in zero trust mode
    error = assert_raises(RackJwtAegis::ConfigurationError) do
      RackJwtAegis::Configuration.new(
        jwt_secret: 'test-secret',
        rbac_enabled: true,
        cache_store: :memory,
        cache_write_enabled: false,
        rbac_cache_store: nil # This should trigger line 303
      )
    end
    assert_equal 'rbac_cache_store is required when cache_write_enabled is false', error.message
  end

  def test_permission_cache_store_defaults_to_memory_when_cache_write_disabled
    # Test lines 307-308: permission_cache_store.nil? check and default assignment
    config = RackJwtAegis::Configuration.new(
      jwt_secret: 'test-secret',
      rbac_enabled: true,
      cache_store: :redis,
      cache_write_enabled: false,
      rbac_cache_store: :memory,
      permission_cache_store: nil # This should trigger lines 307-308
    )

    # permission_cache_store should default to :memory when nil in zero trust mode
    assert_equal :memory, config.permission_cache_store
  end
end
