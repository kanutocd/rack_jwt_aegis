# frozen_string_literal: true

require 'test_helper'

class ConfigurationCoverageHardeningTest < Minitest::Test
  def test_normalizes_every_supported_route_shape
    config = RackJwtAegis::Configuration.new(jwt_secret: 'test-secret')
    entries = [
      { 'path' => '/string-path', 'verbs' => ' get ' },
      { path: '/symbol-verb', verb: :post },
      { 'path' => '/string-verb', 'verb' => ['put', nil, ''] },
      { path: '/symbol-method', methods: :patch },
      { 'path' => '/string-method', 'methods' => ['delete', 'head'] },
      { path: nil, verbs: :get },
      Object.new,
    ]

    routes = config.send(:normalize_skip_route_entries, entries)

    assert_equal 5, routes.length
    assert_equal ['GET'], routes[0][:verbs]
    assert_equal ['POST'], routes[1][:verbs]
    assert_equal ['PUT'], routes[2][:verbs]
    assert_equal ['PATCH'], routes[3][:verbs]
    assert_equal ['DELETE', 'HEAD'], routes[4][:verbs]
  end

  def test_normalizes_empty_and_duplicate_verbs
    config = RackJwtAegis::Configuration.new(jwt_secret: 'test-secret')

    assert_nil config.send(:normalize_skip_verbs, nil)
    assert_nil config.send(:normalize_skip_verbs, [])
    assert_nil config.send(:normalize_skip_verbs, '')
    assert_nil config.send(:normalize_skip_verbs, [nil, ''])
    assert_equal ['GET', 'POST'], config.send(:normalize_skip_verbs, ['get', 'GET', 'post'])
    assert_nil config.send(:normalize_skip_verbs, ' ')
  end

  def test_matches_string_regex_and_invalid_route_paths
    config = RackJwtAegis::Configuration.new(jwt_secret: 'test-secret')

    assert config.send(:route_matches?, { path: '/health', verbs: nil }, '/health', 'GET')
    assert config.send(:route_matches?, { path: %r{/health}, verbs: ['GET'] }, '/health', 'GET')
    refute config.send(:route_matches?, { path: Object.new, verbs: ['GET'] }, '/health', 'GET')
    refute config.send(:route_matches?, { path: '/health', verbs: ['GET'] }, '/health', nil)
    refute config.send(:route_matches?, { path: '/health', verbs: ['GET'] }, '/health', 'POST')
  end

  def test_validates_authentication_header_and_period_settings
    assert_raises(RackJwtAegis::ConfigurationError) do
      RackJwtAegis::Configuration.new(
        jwt_secret: 'test-secret',
        require_authentication_headers: true,
        payload_mapping: {},
        tenant_id_header_name: '',
        tenant_slug_header_name: '',
        user_id_header_name: '',
      )
    end

    assert_raises(RackJwtAegis::ConfigurationError) do
      RackJwtAegis::Configuration.new(jwt_secret: 'test-secret', circuit_breaker_enabled: true,
                                      circuit_breaker_failure_threshold: 0)
    end

    assert_raises(RackJwtAegis::ConfigurationError) do
      RackJwtAegis::Configuration.new(jwt_secret: 'test-secret', circuit_breaker_enabled: true,
                                      circuit_breaker_cooldown_seconds: -1)
    end
  end

  def test_validates_each_required_tenant_header_condition
    assert_raises(RackJwtAegis::ConfigurationError) do
      RackJwtAegis::Configuration.new(
        jwt_secret: 'test-secret', validate_tenant_id: true,
        payload_mapping: { user_id: :user_id }, tenant_id_header_name: ''
      )
    end

    assert_raises(RackJwtAegis::ConfigurationError) do
      RackJwtAegis::Configuration.new(
        jwt_secret: 'test-secret', validate_pathname_slug: true,
        payload_mapping: { user_id: :user_id }, pathname_slug_pattern: nil
      )
    end
  end

  def test_skip_options_predicate
    assert_predicate RackJwtAegis::Configuration.new(jwt_secret: 'test-secret', skip_options_requests: true),
                     :skip_options_requests?
    refute_predicate RackJwtAegis::Configuration.new(jwt_secret: 'test-secret'), :skip_options_requests?
  end

  def test_uses_rails_cache_defaults_when_rails_is_available
    rails = Module.new do
      const_set(:Application, Class.new)
      define_singleton_method(:env) { Struct.new(:development?).new(false) }
      define_singleton_method(:application) do
        Struct.new(:config).new(Struct.new(:cache_store).new(:memory))
      end
    end
    Object.const_set(:Rails, rails)

    config = RackJwtAegis::Configuration.new(jwt_secret: 'test-secret')

    assert_equal :memory, config.rbac_cache_store
  ensure
    Object.send(:remove_const, :Rails) if Object.const_defined?(:Rails)
  end
end

class JwtValidatorCoverageHardeningTest < Minitest::Test
  def test_rejects_invalid_optional_claim_types
    cases = [
      [{ 'user_id' => [] }, 'user_id'],
      [{ 'user_id' => 1, 'tenant_id' => [] }, 'tenant_id'],
      [{ 'user_id' => 'u', 'tenant_id' => 't', 'tenant_slug' => 1 }, 'tenant_slug'],
      [{ 'user_id' => 'u', 'exp' => 'bad', 'iat' => 1 }, 'exp'],
      [{ 'user_id' => 'u', 'exp' => 1, 'iat' => 'bad' }, 'iat'],
      [{ 'user_id' => 'u', 'subdomain' => [] }, 'subdomain'],
      [{ 'user_id' => 'u', 'pathname_slugs' => 'bad' }, 'pathname_slugs'],
    ]

    cases.each do |overrides, claim|
      options = { jwt_secret: 'test-secret' }
      options[:validate_tenant_id] = true if claim == 'tenant_id'
      options[:require_authentication_headers] = true if claim == 'tenant_slug'
      if claim == 'tenant_slug'
        options[:payload_mapping] =
          { user_id: :user_id, tenant_id: :tenant_id, tenant_slug: :tenant_slug }
      end
      options[:require_expiration_claims] = true if ['exp', 'iat'].include?(claim) # rubocop:disable Performance/CollectionLiteralInLoop
      options[:validate_subdomain] = true if claim == 'subdomain'
      options[:validate_pathname_slug] = true if claim == 'pathname_slugs'
      config = RackJwtAegis::Configuration.new(options)
      # rubocop:disable Performance/CollectionLiteralInLoop
      payload = { 'user_id' => 'u', 'tenant_id' => 't', 'tenant_slug' => 'slug',
                  'subdomain' => 'group', 'pathname_slugs' => [] }.merge(overrides)
      # rubocop:enable Performance/CollectionLiteralInLoop
      error = assert_raises(RackJwtAegis::AuthenticationError, "claim #{claim}") do
        RackJwtAegis::JwtValidator.new(config).send(:validate_claim_types, payload)
      end
      assert_match claim, error.message
    end
  end

  def test_accepts_optional_claims_when_valid_or_absent
    config = RackJwtAegis::Configuration.new(jwt_secret: 'test-secret')
    validator = RackJwtAegis::JwtValidator.new(config)

    validator.send(:validate_claim_types, { 'user_id' => 'u' })
    validator.send(:validate_claim_types, { 'user_id' => 'u', 'pathname_slugs' => nil })
  end

  def test_accepts_valid_tenant_id_and_rejects_invalid_header_tenant_id
    config = RackJwtAegis::Configuration.new(jwt_secret: 'test-secret', validate_tenant_id: true)
    validator = RackJwtAegis::JwtValidator.new(config)
    validator.send(:validate_claim_types, { 'user_id' => 'u', 'tenant_id' => 'tenant' })

    header_config = RackJwtAegis::Configuration.new(
      jwt_secret: 'test-secret', require_authentication_headers: true,
      payload_mapping: { user_id: :user_id, tenant_id: :tenant_id, tenant_slug: :tenant_slug }
    )
    error = assert_raises(RackJwtAegis::AuthenticationError) do
      RackJwtAegis::JwtValidator.new(header_config).send(
        :validate_claim_types, { 'user_id' => 'u', 'tenant_id' => [], 'tenant_slug' => 'slug' }
      )
    end
    assert_match 'tenant_id', error.message
  end

  def test_accepts_valid_pathname_slugs
    config = RackJwtAegis::Configuration.new(jwt_secret: 'test-secret', validate_pathname_slug: true)
    RackJwtAegis::JwtValidator.new(config).send(
      :validate_claim_types, { 'user_id' => 'u', 'pathname_slugs' => ['company'] }
    )
  end
end

class CacheAdapterCoverageHardeningTest < Minitest::Test
  def test_reports_missing_optional_adapter_dependencies
    original_redis = Redis if defined?(Redis)
    Object.send(:remove_const, :Redis) if defined?(Redis)

    stub_require('redis') do
      assert_raises(RackJwtAegis::CacheError) { RackJwtAegis::RedisAdapter.new }
    end

    original_dalli = Dalli if defined?(Dalli)
    Object.send(:remove_const, :Dalli) if defined?(Dalli)

    stub_require('dalli') do
      assert_raises(RackJwtAegis::CacheError) { RackJwtAegis::MemcachedAdapter.new }
    end
  ensure
    Object.const_set(:Redis, original_redis) if original_redis
    Object.const_set(:Dalli, original_dalli) if original_dalli
  end

  private

  def stub_require(missing_name)
    original = Kernel.instance_method(:require)
    Kernel.module_eval do
      define_method(:require) do |name|
        raise LoadError, name if name == missing_name

        original.bind_call(self, name)
      end
      private :require
    end
    yield
  ensure
    Kernel.module_eval do
      define_method(:require, original)
      private :require
    end
  end
end

class RbacCoverageHardeningTest < Minitest::Test
  def setup
    @config = RackJwtAegis::Configuration.new(
      jwt_secret: 'test-secret', rbac_enabled: true,
      rbac_cache_store: :memory, permissions_cache_store: :memory
    )
    @manager = RackJwtAegis::RbacManager.new(@config)
    @request = Rack::Request.new(Rack::MockRequest.env_for('/api/v1/users', method: 'GET'))
  end

  def test_handles_empty_and_invalid_rbac_inputs
    disabled = RackJwtAegis::RbacManager.new(RackJwtAegis::Configuration.new(jwt_secret: 'test-secret'))

    assert_nil disabled.send(:check_cached_permission, 'key')
    assert_nil disabled.send(:cache_permission_result, 'key', true)
    assert_nil disabled.send(:remove_stale_permission, 'key', 'reason')
    assert_nil disabled.send(:nuke_user_permissions_cache, 'reason')
    refute @manager.send(:check_role_permissions?, nil, @request)
    refute @manager.send(:check_role_permissions?, [], @request)
    assert_nil @manager.send(:find_matching_permission, nil, @request)
    assert_nil disabled.send(:cache_matched_permission, 'user', @request)
  end

  def test_handles_role_and_permission_matches
    @request.env['rack_jwt_aegis.user_roles'] = ['missing']

    refute @manager.send(:check_rbac_format?, 'user', @request, { 'permissions' => {} })

    assert @manager.send(:check_role_permissions?, ['users:get'], @request)
    refute @manager.send(:check_role_permissions?, ['users:post'], @request)
    assert_equal 'users:get', @manager.send(:find_matching_permission, ['users:get'], @request)
    assert_nil @manager.send(:find_matching_permission, ['users:post'], @request)
    refute @manager.send(:permission_matches?, nil, 'users', 'get')
    refute @manager.send(:permission_matches?, 'invalid', 'users', 'get')
    refute @manager.send(:permission_matches?, 'users:post', 'users', 'get')
    assert @manager.send(:permission_matches?, 'users:*', 'users', 'get')
    assert @manager.send(:path_matches?, '%r{users}', 'users')
    refute @manager.send(:path_matches?, '%r{[}', 'users')
  end

  def test_handles_pathname_fallback_and_nil_permissions
    config = RackJwtAegis::Configuration.new(
      jwt_secret: 'test-secret', pathname_slug_pattern: %r{^/api/v1/([^/]+)/},
    )
    manager = RackJwtAegis::RbacManager.new(config)
    unmatched = Rack::Request.new(Rack::MockRequest.env_for('/health'))

    assert_equal 'health', manager.send(:extract_api_path_from_request, unmatched)
    refute manager.send(:validate_rbac_cache_format, { last_update: 1, permissions: nil })

    no_capture = RackJwtAegis::Configuration.new(
      jwt_secret: 'test-secret', pathname_slug_pattern: %r{^/api/v1/[^/]+},
    )
    no_capture_manager = RackJwtAegis::RbacManager.new(no_capture)
    no_capture_request = Rack::Request.new(Rack::MockRequest.env_for('/api/v1/company/users'))

    assert_equal 'company/users', no_capture_manager.send(:extract_api_path_from_request, no_capture_request)

    leading_slash = RackJwtAegis::Configuration.new(
      jwt_secret: 'test-secret', pathname_slug_pattern: %r{^/api/v1/([^/]+)},
    )
    leading_slash_manager = RackJwtAegis::RbacManager.new(leading_slash)
    leading_slash_request = Rack::Request.new(Rack::MockRequest.env_for('/api/v1/company/users'))

    assert_equal 'users', leading_slash_manager.send(:extract_api_path_from_request, leading_slash_request)
  end

  def test_handles_cache_read_and_write_errors
    failing_cache = Class.new do
      def read(*) = raise(RackJwtAegis::CacheError, 'read failed')
      def write(*) = raise(RackJwtAegis::CacheError, 'write failed')
    end.new

    @manager.instance_variable_set(:@permissions_cache, failing_cache)

    assert_nil @manager.send(:check_cached_permission, 'key')
    assert_nil @manager.send(:cache_matched_permission, 'user', @request)
  end
end

class MiddlewareCoverageHardeningTest < Minitest::Test
  def test_handles_a_header_object_without_a_token
    middleware = RackJwtAegis::Middleware.new(->(_env) { [200, {}, []] }, jwt_secret: 'test-secret')
    header = Class.new do
      def empty? = false
      def match(*) = Class.new { def [](*) = nil }.new
    end.new
    request = Class.new do
      define_method(:get_header) { |_name| header }
    end.new

    assert_raises(RackJwtAegis::AuthenticationError) { middleware.send(:extract_jwt_token, request) }
  end

  def test_records_success_with_a_circuit_breaker
    middleware = RackJwtAegis::Middleware.new(
      ->(_env) { [200, {}, []] }, jwt_secret: 'test-secret', circuit_breaker_enabled: true
    )
    env = Rack::MockRequest.env_for(
      'http://example.com/api/users',
      'HTTP_AUTHORIZATION' => "Bearer #{generate_jwt_token}",
    )

    assert_equal 200, middleware.call(env).first
  end
end

class MultiTenantCoverageHardeningTest < Minitest::Test
  def test_rejects_missing_claim_for_required_header
    config = RackJwtAegis::Configuration.new(
      jwt_secret: 'test-secret', require_authentication_headers: true,
      payload_mapping: { user_id: :user_id, tenant_id: :tenant_id, tenant_slug: :tenant_slug }
    )
    validator = RackJwtAegis::MultiTenantValidator.new(config)
    request = Rack::Request.new(Rack::MockRequest.env_for(
                                  'http://example.com/',
                                  'HTTP_X_TENANT_ID' => 'tenant',
                                  'HTTP_X_TENANT_SLUG' => 'slug',
                                  'HTTP_X_USER_ID' => 'user',
                                ))

    error = assert_raises(RackJwtAegis::AuthorizationError) do
      validator.validate(request, { 'tenant_id' => 'tenant', 'tenant_slug' => nil, 'user_id' => 'user' })
    end
    assert_match 'tenant_slug', error.message
  end
end
