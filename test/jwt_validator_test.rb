# frozen_string_literal: true

require 'test_helper'

class JwtValidatorTest < Minitest::Test
  def setup
    @config = RackJwtAegis::Configuration.new(basic_config)
    @validator = RackJwtAegis::JwtValidator.new(@config)
  end

  def test_validates_valid_jwt_token
    token = generate_jwt_token
    payload = @validator.validate(token)

    assert_equal 123, payload['user_id']
    assert_equal 456, payload['company_group_id']
  end

  def test_rejects_expired_token
    expired_payload = valid_jwt_payload.merge('exp' => Time.now.to_i - 3600)
    token = generate_jwt_token(expired_payload)

    error = assert_raises(RackJwtAegis::AuthenticationError) do
      @validator.validate(token)
    end
    assert_match(/expired/, error.message)
  end

  def test_rejects_invalid_signature
    token = generate_jwt_token(valid_jwt_payload, 'wrong-secret')

    error = assert_raises(RackJwtAegis::AuthenticationError) do
      @validator.validate(token)
    end
    assert_match(/verification failed/, error.message)
  end

  def test_validates_payload_structure
    invalid_payload = valid_jwt_payload.merge('user_id' => nil)
    token = generate_jwt_token(invalid_payload)

    assert_raises(RackJwtAegis::AuthenticationError) do
      @validator.validate(token)
    end
  end

  def test_validates_required_multi_tenant_claims
    config = RackJwtAegis::Configuration.new(
      basic_config.merge(validate_subdomain: true),
    )
    validator = RackJwtAegis::JwtValidator.new(config)

    # Missing company_group_domain
    payload = valid_jwt_payload.tap { |p| p.delete('company_group_domain') }
    token = generate_jwt_token(payload)

    assert_raises(RackJwtAegis::AuthenticationError) do
      validator.validate(token)
    end
  end

  def test_validates_company_slugs_format
    config = RackJwtAegis::Configuration.new(
      basic_config.merge(validate_company_slug: true),
    )
    validator = RackJwtAegis::JwtValidator.new(config)

    # company_slugs should be array, not string
    payload = valid_jwt_payload.merge('company_slugs' => 'invalid-format')
    token = generate_jwt_token(payload)

    assert_raises(RackJwtAegis::AuthenticationError) do
      validator.validate(token)
    end
  end
end
