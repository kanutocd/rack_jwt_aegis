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
    assert_equal 456, payload['tenant_id']
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
    assert_equal 'JWT signature verification failed', error.message
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

    # Missing subdomain
    payload = valid_jwt_payload.tap { |p| p.delete('subdomain') }
    token = generate_jwt_token(payload)

    assert_raises(RackJwtAegis::AuthenticationError) do
      validator.validate(token)
    end
  end

  def test_requires_expiration_claims_when_configured
    config = RackJwtAegis::Configuration.new(basic_config.merge(require_expiration_claims: true))
    validator = RackJwtAegis::JwtValidator.new(config)
    payload = valid_jwt_payload.dup
    payload.delete('exp')
    token = generate_jwt_token(payload)

    error = assert_raises(RackJwtAegis::AuthenticationError) do
      validator.validate(token)
    end

    assert_match(/JWT payload missing required claims: exp/, error.message)
  end

  def test_validates_required_authentication_header_claims
    config = RackJwtAegis::Configuration.new(basic_config.merge(
                                               require_authentication_headers: true,
                                               payload_mapping: {
                                                 user_id: :user_id,
                                                 tenant_id: :organization_id,
                                                 tenant_slug: :organization_slug,
                                               },
                                             ))
    validator = RackJwtAegis::JwtValidator.new(config)
    token = generate_jwt_token(
      'user_id' => 'user-123',
      'organization_id' => 'org-123',
      'organization_slug' => 'acme-village',
      'exp' => Time.now.to_i + 3600,
      'iat' => Time.now.to_i,
    )

    payload = validator.validate(token)

    assert_equal 'org-123', payload['organization_id']
  end

  def test_validates_pathname_slugs_format
    config = RackJwtAegis::Configuration.new(
      basic_config.merge(validate_pathname_slug: true),
    )
    validator = RackJwtAegis::JwtValidator.new(config)

    # pathname_slugs should be array, not string
    payload = valid_jwt_payload.merge('pathname_slugs' => 'invalid-format')
    token = generate_jwt_token(payload)

    assert_raises(RackJwtAegis::AuthenticationError) do
      validator.validate(token)
    end
  end
end
