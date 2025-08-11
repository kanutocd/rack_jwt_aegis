# frozen_string_literal: true

require 'test_helper'

class RackJwtAegisTest < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil ::RackJwtAegis::VERSION
  end

  def test_basic_middleware_initialization
    middleware = RackJwtAegis::Middleware.new(mock_app, basic_config)

    assert_instance_of RackJwtAegis::Middleware, middleware
  end

  def test_configuration_validation
    # Should raise error for missing jwt_secret
    assert_raises(RackJwtAegis::ConfigurationError) do
      RackJwtAegis::Configuration.new({})
    end

    # Should work with valid config
    config = RackJwtAegis::Configuration.new(basic_config)

    assert_equal 'test-secret', config.jwt_secret
    assert_equal 'HS256', config.jwt_algorithm
  end

  def test_skip_paths_functionality
    config = RackJwtAegis::Configuration.new(
      basic_config.merge(skip_paths: ['/health', '/login']),
    )

    assert config.skip_path?('/health')
    assert config.skip_path?('/login')
    refute config.skip_path?('/api/users')
  end

  def test_feature_toggles
    config = RackJwtAegis::Configuration.new(
      basic_config.merge(
        validate_subdomain: true,
        validate_pathname_slug: true,
        rbac_enabled: true,
        cache_store: :memory,
        cache_write_enabled: true,
      ),
    )

    assert_predicate config, :validate_subdomain?
    assert_predicate config, :validate_pathname_slug?
    assert_predicate config, :rbac_enabled?
  end
end
