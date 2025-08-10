# frozen_string_literal: true

require 'test_helper'

class ConfigurationTest < Minitest::Test
  def test_initialization_with_empty_options
    assert_raises(RackJwtAegis::ConfigurationError) do
      RackJwtAegis::Configuration.new({})
    end
  end

  def test_initialization_with_minimal_valid_options
    config = RackJwtAegis::Configuration.new(jwt_secret: 'test-secret')

    assert_equal 'test-secret', config.jwt_secret
    assert_equal 'HS256', config.jwt_algorithm
    refute_predicate config, :validate_subdomain?
    refute_predicate config, :validate_pathname_slug?
    refute_predicate config, :rbac_enabled?
  end

  def test_initialization_with_all_options
    options = {
      jwt_secret: 'test-secret',
      jwt_algorithm: 'HS512',
      validate_subdomain: true,
      validate_pathname_slug: true,
      rbac_enabled: true,
      tenant_id_header_name: 'X-Custom-Header',
      pathname_slug_pattern: %r{^/custom/([^/]+)/},
      skip_paths: ['/health', '/status'],
      cache_store: :redis,
      cache_options: { url: 'redis://localhost:6379' },
      cache_write_enabled: true,
      custom_payload_validator: ->(_payload, _request) { true },
      unauthorized_response: { error: 'Custom unauthorized' },
      forbidden_response: { error: 'Custom forbidden' },
      debug_mode: true,
    }

    config = RackJwtAegis::Configuration.new(options)

    assert_equal 'test-secret', config.jwt_secret
    assert_equal 'HS512', config.jwt_algorithm
    assert_predicate config, :validate_subdomain?
    assert_predicate config, :validate_pathname_slug?
    assert_predicate config, :rbac_enabled?
    assert_equal 'X-Custom-Header', config.tenant_id_header_name
    assert_equal(%r{^/custom/([^/]+)/}, config.pathname_slug_pattern)
    assert_equal ['/health', '/status'], config.skip_paths
    assert_equal :redis, config.cache_store
    assert_equal({ url: 'redis://localhost:6379' }, config.cache_options)
    assert_predicate config, :cache_write_enabled?
    assert_respond_to config.custom_payload_validator, :call
    assert_equal({ error: 'Custom unauthorized' }, config.unauthorized_response)
    assert_equal({ error: 'Custom forbidden' }, config.forbidden_response)
    assert_predicate config, :debug_mode?
  end

  def test_default_values
    config = RackJwtAegis::Configuration.new(jwt_secret: 'test-secret')

    assert_equal 'HS256', config.jwt_algorithm
    assert_equal 'X-Tenant-Id', config.tenant_id_header_name
    assert_equal(%r{^/api/v1/([^/]+)/}, config.pathname_slug_pattern)
    assert_empty config.skip_paths
    refute_predicate config, :cache_write_enabled?
    refute_predicate config, :debug_mode?

    expected_payload_mapping = {
      user_id: :user_id,
      tenant_id: :tenant_id,
      subdomain: :subdomain,
      pathname_slugs: :pathname_slugs,
    }

    assert_equal expected_payload_mapping, config.payload_mapping

    assert_equal({ error: 'Authentication required' }, config.unauthorized_response)
    assert_equal({ error: 'Access denied' }, config.forbidden_response)
  end

  def test_unknown_configuration_option
    error = assert_raises(RackJwtAegis::ConfigurationError) do
      RackJwtAegis::Configuration.new(
        jwt_secret: 'test-secret',
        unknown_option: 'value',
      )
    end
    assert_match(/Unknown configuration option: unknown_option/, error.message)
  end

  # JWT Settings Validation Tests
  def test_missing_jwt_secret
    error = assert_raises(RackJwtAegis::ConfigurationError) do
      RackJwtAegis::Configuration.new({})
    end
    assert_match(/jwt_secret is required/, error.message)
  end

  def test_empty_jwt_secret
    error = assert_raises(RackJwtAegis::ConfigurationError) do
      RackJwtAegis::Configuration.new(jwt_secret: '')
    end
    assert_match(/jwt_secret is required/, error.message)
  end

  def test_nil_jwt_secret
    error = assert_raises(RackJwtAegis::ConfigurationError) do
      RackJwtAegis::Configuration.new(jwt_secret: nil)
    end
    assert_match(/jwt_secret is required/, error.message)
  end

  def test_valid_jwt_algorithms
    valid_algorithms = ['HS256', 'HS384', 'HS512', 'RS256', 'RS384', 'RS512', 'ES256', 'ES384', 'ES512']

    valid_algorithms.each do |algorithm|
      config = RackJwtAegis::Configuration.new(
        jwt_secret: 'test-secret',
        jwt_algorithm: algorithm,
      )

      assert_equal algorithm, config.jwt_algorithm
    end
  end

  def test_invalid_jwt_algorithm
    error = assert_raises(RackJwtAegis::ConfigurationError) do
      RackJwtAegis::Configuration.new(
        jwt_secret: 'test-secret',
        jwt_algorithm: 'INVALID',
      )
    end
    assert_match(/Unsupported JWT algorithm: INVALID/, error.message)
  end

  # Cache Settings Validation Tests
  def test_rbac_enabled_without_cache_store
    error = assert_raises(RackJwtAegis::ConfigurationError) do
      RackJwtAegis::Configuration.new(
        jwt_secret: 'test-secret',
        rbac_enabled: true,
      )
    end
    assert_match(/cache_store or rbac_cache_store is required when RBAC is enabled/, error.message)
  end

  def test_rbac_enabled_with_cache_store_and_write_enabled
    config = RackJwtAegis::Configuration.new(
      jwt_secret: 'test-secret',
      rbac_enabled: true,
      cache_store: :memory,
      cache_write_enabled: true,
    )

    assert_predicate config, :rbac_enabled?
    assert_equal :memory, config.cache_store
    assert_predicate config, :cache_write_enabled?
  end

  def test_rbac_enabled_without_write_access_requires_separate_caches
    error = assert_raises(RackJwtAegis::ConfigurationError) do
      RackJwtAegis::Configuration.new(
        jwt_secret: 'test-secret',
        rbac_enabled: true,
        cache_store: :memory,
        cache_write_enabled: false,
      )
    end
    assert_match(/rbac_cache_store is required when cache_write_enabled is false/, error.message)
  end

  def test_rbac_enabled_with_separate_caches_zero_trust_mode
    config = RackJwtAegis::Configuration.new(
      jwt_secret: 'test-secret',
      rbac_enabled: true,
      rbac_cache_store: :redis,
      permission_cache_store: :memory,
      cache_write_enabled: false,
    )

    assert_predicate config, :rbac_enabled?
    assert_equal :redis, config.rbac_cache_store
    assert_equal :memory, config.permission_cache_store
    refute_predicate config, :cache_write_enabled?
  end

  def test_rbac_enabled_with_rbac_cache_store_only
    config = RackJwtAegis::Configuration.new(
      jwt_secret: 'test-secret',
      rbac_enabled: true,
      rbac_cache_store: :redis,
    )

    assert_predicate config, :rbac_enabled?
    assert_equal :redis, config.rbac_cache_store
    assert_equal :memory, config.permission_cache_store # Default fallback
  end

  # Multi-Tenant Settings Validation Tests
  def test_validate_pathname_slug_without_pattern
    error = assert_raises(RackJwtAegis::ConfigurationError) do
      RackJwtAegis::Configuration.new(
        jwt_secret: 'test-secret',
        validate_pathname_slug: true,
        pathname_slug_pattern: nil,
      )
    end
    assert_match(/pathname_slug_pattern is required when validate_pathname_slug is true/, error.message)
  end

  def test_validate_subdomain_without_payload_mapping
    # Remove the required payload mapping key
    error = assert_raises(RackJwtAegis::ConfigurationError) do
      RackJwtAegis::Configuration.new(
        jwt_secret: 'test-secret',
        validate_subdomain: true,
        payload_mapping: { user_id: :user_id }, # Missing subdomain
      )
    end
    assert_match(/payload_mapping must include :subdomain when validate_subdomain is true/, error.message)
  end

  def test_validate_pathname_slug_without_payload_mapping
    error = assert_raises(RackJwtAegis::ConfigurationError) do
      RackJwtAegis::Configuration.new(
        jwt_secret: 'test-secret',
        validate_pathname_slug: true,
        payload_mapping: { user_id: :user_id }, # Missing pathname_slugs
      )
    end
    assert_match(/payload_mapping must include :pathname_slugs when validate_pathname_slug is true/, error.message)
  end

  # Skip Path Tests
  def test_skip_path_with_string_paths
    config = RackJwtAegis::Configuration.new(
      jwt_secret: 'test-secret',
      skip_paths: ['/health', '/status', '/api/public'],
    )

    assert config.skip_path?('/health')
    assert config.skip_path?('/status')
    assert config.skip_path?('/api/public')
    refute config.skip_path?('/api/private')
    refute config.skip_path?('/health/deep')
  end

  def test_skip_path_with_regex_paths
    config = RackJwtAegis::Configuration.new(
      jwt_secret: 'test-secret',
      skip_paths: [%r{^/public}, %r{/health$}, '/exact-match'],
    )

    assert config.skip_path?('/public')
    assert config.skip_path?('/public/anything')
    assert config.skip_path?('/api/health')
    assert config.skip_path?('/exact-match')
    refute config.skip_path?('/private')
    refute config.skip_path?('/health/check')
    refute config.skip_path?('/exact-match-not')
  end

  def test_skip_path_with_empty_paths
    config = RackJwtAegis::Configuration.new(
      jwt_secret: 'test-secret',
      skip_paths: [],
    )

    refute config.skip_path?('/any-path')
  end

  def test_skip_path_with_nil_paths
    config = RackJwtAegis::Configuration.new(
      jwt_secret: 'test-secret',
      skip_paths: nil,
    )

    refute config.skip_path?('/any-path')
  end

  def test_skip_path_with_invalid_path_types
    config = RackJwtAegis::Configuration.new(
      jwt_secret: 'test-secret',
      skip_paths: ['/valid', 123, nil, Object.new],
    )

    assert config.skip_path?('/valid')
    refute config.skip_path?('/invalid')
  end

  # Payload Mapping Tests
  def test_payload_key_mapping
    config = RackJwtAegis::Configuration.new(
      jwt_secret: 'test-secret',
      payload_mapping: {
        user_id: :sub,
        tenant_id: :company_id,
        subdomain: :domain,
        pathname_slugs: :accessible_companies,
      },
    )

    assert_equal :sub, config.payload_key(:user_id)
    assert_equal :company_id, config.payload_key(:tenant_id)
    assert_equal :domain, config.payload_key(:subdomain)
    assert_equal :accessible_companies, config.payload_key(:pathname_slugs)
  end

  def test_payload_key_with_missing_mapping
    config = RackJwtAegis::Configuration.new(jwt_secret: 'test-secret')

    # Should return the original key when no mapping exists
    assert_equal :unmapped_key, config.payload_key(:unmapped_key)
  end

  def test_payload_key_with_nil_mapping
    config = RackJwtAegis::Configuration.new(
      jwt_secret: 'test-secret',
      payload_mapping: nil,
    )

    assert_equal :user_id, config.payload_key(:user_id)
  end

  # Boolean Helper Method Tests
  def test_boolean_helper_methods
    config = RackJwtAegis::Configuration.new(
      jwt_secret: 'test-secret',
      validate_subdomain: true,
      validate_pathname_slug: false,
      rbac_enabled: true,
      cache_store: :memory, # Required since rbac_enabled is true
      debug_mode: false,
      cache_write_enabled: true,
    )

    assert_predicate config, :validate_subdomain?
    refute_predicate config, :validate_pathname_slug?
    assert_predicate config, :rbac_enabled?
    refute_predicate config, :debug_mode?
    assert_predicate config, :cache_write_enabled?
  end

  def test_boolean_helper_methods_with_falsy_values
    config = RackJwtAegis::Configuration.new(
      jwt_secret: 'test-secret',
      validate_subdomain: nil,
      validate_pathname_slug: false,
      rbac_enabled: 0,
      debug_mode: '',
      cache_write_enabled: nil,
    )

    refute_predicate config, :validate_subdomain?
    refute_predicate config, :validate_pathname_slug?
    refute_predicate config, :rbac_enabled?
    refute_predicate config, :debug_mode?
    refute_predicate config, :cache_write_enabled?
  end

  def test_boolean_helper_methods_with_a_string_false
    config = RackJwtAegis::Configuration.new(
      jwt_secret: 'test-secret',
      validate_subdomain: 'false',
    )

    refute_predicate config, :validate_subdomain?
  end

  def test_boolean_helper_methods_with_truthy_values
    config = RackJwtAegis::Configuration.new(
      jwt_secret: 'test-secret',
      validate_subdomain: 'yes',
      validate_pathname_slug: 1,
      rbac_enabled: 'true',
      cache_store: :memory, # Required since rbac_enabled is 'true' (truthy)
      debug_mode: [1],
      cache_write_enabled: { enabled: true },
    )

    assert_predicate config, :validate_subdomain?
    assert_predicate config, :validate_pathname_slug?
    assert_predicate config, :rbac_enabled?
    assert_predicate config, :debug_mode?
    assert_predicate config, :cache_write_enabled?
  end

  # Integration Tests - Real-world Configuration Scenarios
  def test_basic_jwt_only_configuration
    config = RackJwtAegis::Configuration.new(
      jwt_secret: ENV['JWT_SECRET'] || 'test-secret',
    )

    assert config.jwt_secret
    assert_equal 'HS256', config.jwt_algorithm
    refute_predicate config, :validate_subdomain?
    refute_predicate config, :validate_pathname_slug?
    refute_predicate config, :rbac_enabled?
    assert_empty config.skip_paths
  end

  def test_multi_tenant_saas_configuration
    config = RackJwtAegis::Configuration.new(
      jwt_secret: 'test-secret',
      validate_subdomain: true,
      validate_pathname_slug: true,
      tenant_id_header_name: 'X-Tenant-Id',
      skip_paths: ['/health', '/api/v1/login'],
    )

    assert_predicate config, :validate_subdomain?
    assert_predicate config, :validate_pathname_slug?
    assert_equal 'X-Tenant-Id', config.tenant_id_header_name
    assert config.skip_path?('/health')
    assert config.skip_path?('/api/v1/login')
    refute_predicate config, :rbac_enabled?
  end

  def test_enterprise_rbac_shared_cache_configuration
    config = RackJwtAegis::Configuration.new(
      jwt_secret: 'test-secret',
      validate_subdomain: true,
      validate_pathname_slug: true,
      rbac_enabled: true,
      cache_store: :redis,
      cache_options: { url: 'redis://localhost:6379' },
      cache_write_enabled: true,
    )

    assert_predicate config, :validate_subdomain?
    assert_predicate config, :validate_pathname_slug?
    assert_predicate config, :rbac_enabled?
    assert_equal :redis, config.cache_store
    assert_predicate config, :cache_write_enabled?
    assert_equal({ url: 'redis://localhost:6379' }, config.cache_options)
  end

  def test_zero_trust_rbac_configuration
    config = RackJwtAegis::Configuration.new(
      jwt_secret: 'test-secret',
      rbac_enabled: true,
      rbac_cache_store: :redis,
      rbac_cache_options: { url: 'redis://app:6379' },
      permission_cache_store: :memory,
      cache_write_enabled: false,
    )

    assert_predicate config, :rbac_enabled?
    assert_equal :redis, config.rbac_cache_store
    assert_equal :memory, config.permission_cache_store
    refute_predicate config, :cache_write_enabled?
    assert_equal({ url: 'redis://app:6379' }, config.rbac_cache_options)
  end

  def test_development_configuration
    config = RackJwtAegis::Configuration.new(
      jwt_secret: 'dev-secret',
      debug_mode: true,
      skip_paths: ['/health', '/dev', %r{^/assets}],
    )

    assert_predicate config, :debug_mode?
    assert config.skip_path?('/health')
    assert config.skip_path?('/dev')
    assert config.skip_path?('/assets/image.png')
    refute config.skip_path?('/api/secure')
  end

  def test_custom_payload_mapping_configuration
    config = RackJwtAegis::Configuration.new(
      jwt_secret: 'test-secret',
      validate_subdomain: true,
      validate_pathname_slug: true,
      payload_mapping: {
        user_id: :sub,
        tenant_id: :org_id,
        subdomain: :tenant_domain,
        pathname_slugs: :accessible_orgs,
      },
    )

    assert_equal :sub, config.payload_key(:user_id)
    assert_equal :org_id, config.payload_key(:tenant_id)
    assert_equal :tenant_domain, config.payload_key(:subdomain)
    assert_equal :accessible_orgs, config.payload_key(:pathname_slugs)
  end

  def test_custom_response_configuration
    unauthorized_response = { error: 'Please login', code: 4001 }
    forbidden_response = { error: 'Access forbidden', code: 4003 }

    config = RackJwtAegis::Configuration.new(
      jwt_secret: 'test-secret',
      unauthorized_response: unauthorized_response,
      forbidden_response: forbidden_response,
    )

    assert_equal unauthorized_response, config.unauthorized_response
    assert_equal forbidden_response, config.forbidden_response
  end

  def test_custom_validator_configuration
    validator = ->(payload, request) do
      payload['role'] == 'admin' && request.path.start_with?('/admin')
    end

    config = RackJwtAegis::Configuration.new(
      jwt_secret: 'test-secret',
      custom_payload_validator: validator,
    )

    assert_equal validator, config.custom_payload_validator
    assert_respond_to config.custom_payload_validator, :call
  end

  # Edge Cases and Error Conditions
  def test_configuration_immutability_after_creation
    config = RackJwtAegis::Configuration.new(jwt_secret: 'test-secret')

    # Configuration should be mutable (setters available)
    config.debug_mode = true

    assert_predicate config, :debug_mode?

    config.skip_paths = ['/new-path']

    assert config.skip_path?('/new-path')
  end

  def test_complex_skip_paths_scenarios
    complex_patterns = [
      '/health',
      %r{^/api/v[12]/public},
      %r{/docs(?:/.*)?$},
      '/metrics',
      %r{^/webhooks/[a-f0-9]+$},
    ]

    config = RackJwtAegis::Configuration.new(
      jwt_secret: 'test-secret',
      skip_paths: complex_patterns,
    )

    # String matches
    assert config.skip_path?('/health')
    assert config.skip_path?('/metrics')

    # Regex matches
    assert config.skip_path?('/api/v1/public')
    assert config.skip_path?('/api/v2/public/users')
    assert config.skip_path?('/docs')
    assert config.skip_path?('/docs/api')
    assert config.skip_path?('/webhooks/abc123def456')

    # Non-matches
    refute config.skip_path?('/api/v3/public')
    refute config.skip_path?('/private')
    refute config.skip_path?('/webhooks/invalid-format')
    refute config.skip_path?('/health/deep')
  end

  def test_all_jwt_algorithms_validation
    algorithms = ['HS256', 'HS384', 'HS512', 'RS256', 'RS384', 'RS512', 'ES256', 'ES384', 'ES512']

    algorithms.each do |algorithm|
      config = RackJwtAegis::Configuration.new(
        jwt_secret: 'test-secret',
        jwt_algorithm: algorithm,
      )

      assert_equal algorithm, config.jwt_algorithm
    end
  end

  def test_configuration_with_symbol_and_string_keys
    # Test that configuration works with both symbol and string keys
    config = RackJwtAegis::Configuration.new(
      'jwt_secret' => 'test-secret',
      'jwt_algorithm' => 'HS512',
      'debug_mode' => true,
    )

    assert_equal 'test-secret', config.jwt_secret
    assert_equal 'HS512', config.jwt_algorithm
    assert_predicate config, :debug_mode?
  end
end
