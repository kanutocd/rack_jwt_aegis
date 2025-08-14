# frozen_string_literal: true

require 'test_helper'

class JwtValidatorComprehensiveTest < Minitest::Test
  def setup
    @config = RackJwtAegis::Configuration.new(basic_config)
    @validator = RackJwtAegis::JwtValidator.new(@config)
  end

  def test_validate_expired_token
    expired_payload = valid_jwt_payload.merge('exp' => Time.now.to_i - 3600)
    expired_token = generate_jwt_token(expired_payload)

    error = assert_raises(RackJwtAegis::AuthenticationError) do
      @validator.validate(expired_token)
    end
    assert_equal 'JWT token has expired', error.message
  end

  def test_validate_immature_token
    future_payload = valid_jwt_payload.merge('nbf' => Time.now.to_i + 3600)
    future_token = generate_jwt_token(future_payload)

    error = assert_raises(RackJwtAegis::AuthenticationError) do
      @validator.validate(future_token)
    end
    assert_equal 'JWT token not yet valid', error.message
  end

  def test_validate_future_iat_token
    future_iat_payload = valid_jwt_payload.merge('iat' => Time.now.to_i + 3600)
    future_iat_token = generate_jwt_token(future_iat_payload)

    error = assert_raises(RackJwtAegis::AuthenticationError) do
      @validator.validate(future_iat_token)
    end
    assert_equal 'JWT token issued in the future', error.message
  end

  def test_validate_invalid_token_format
    error = assert_raises(RackJwtAegis::AuthenticationError) do
      @validator.validate('invalid.token.format')
    end
    assert_match(/Invalid JWT token/, error.message)
  end

  def test_validate_wrong_signature
    wrong_secret_token = generate_jwt_token(valid_jwt_payload, 'wrong-secret')

    error = assert_raises(RackJwtAegis::AuthenticationError) do
      @validator.validate(wrong_secret_token)
    end
    assert_equal 'JWT signature verification failed', error.message
  end

  def test_validate_malformed_token
    error = assert_raises(RackJwtAegis::AuthenticationError) do
      @validator.validate('not.a.jwt')
    end
    assert_match(/Invalid JWT token/, error.message)
  end

  def test_validate_payload_structure_non_hash
    # This test simulates what would happen if JWT.decode returned something other than a hash
    # We'll mock the JWT.decode method to return an array
    JWT.stubs(:decode).returns([['not', 'a', 'hash'], {}])

    error = assert_raises(RackJwtAegis::AuthenticationError) do
      @validator.validate('any_token')
    end
    assert_match(/Invalid JWT payload structure/, error.message)
  end

  def test_validate_required_claims_missing_user_id
    payload_without_user_id = { 'role' => 'admin' }
    token = generate_jwt_token(payload_without_user_id)

    error = assert_raises(RackJwtAegis::AuthenticationError) do
      @validator.validate(token)
    end
    assert_match(/JWT payload missing required claims: user_id/, error.message)
  end

  def test_validate_required_claims_with_subdomain_enabled
    config = RackJwtAegis::Configuration.new(basic_config.merge(validate_tenant_id: true, validate_subdomain: true))
    validator = RackJwtAegis::JwtValidator.new(config)

    # Missing tenant_id and subdomain
    incomplete_payload = { 'user_id' => 123 }
    token = generate_jwt_token(incomplete_payload)

    error = assert_raises(RackJwtAegis::AuthenticationError) do
      validator.validate(token)
    end
    assert_match(/JWT payload missing required claims/, error.message)
    assert_match(/tenant_id/, error.message)
    assert_match(/subdomain/, error.message)
  end

  def test_validate_required_claims_with_pathname_slug_enabled
    config = RackJwtAegis::Configuration.new(basic_config.merge(validate_pathname_slug: true))
    validator = RackJwtAegis::JwtValidator.new(config)

    # Missing pathname_slugs
    incomplete_payload = { 'user_id' => 123 }
    token = generate_jwt_token(incomplete_payload)

    error = assert_raises(RackJwtAegis::AuthenticationError) do
      validator.validate(token)
    end
    assert_match(/JWT payload missing required claims: pathname_slugs/, error.message)
  end

  def test_validate_claim_types_invalid_user_id_format
    payload = { 'user_id' => { 'invalid' => 'object' } }
    token = generate_jwt_token(payload)

    error = assert_raises(RackJwtAegis::AuthenticationError) do
      @validator.validate(token)
    end
    assert_match(/Invalid user_id format in JWT payload/, error.message)
  end

  def test_validate_claim_types_valid_user_id_formats
    # Test numeric user_id
    payload = { 'user_id' => 123 }
    token = generate_jwt_token(payload)
    result = @validator.validate(token)

    assert_equal 123, result['user_id']

    # Test string user_id
    payload = { 'user_id' => '123' }
    token = generate_jwt_token(payload)
    result = @validator.validate(token)

    assert_equal '123', result['user_id']
  end

  def test_validate_claim_types_invalid_tenant_id_format_with_subdomain
    config = RackJwtAegis::Configuration.new(basic_config.merge(validate_tenant_id: true, validate_subdomain: true))
    validator = RackJwtAegis::JwtValidator.new(config)

    payload = {
      'user_id' => 123,
      'tenant_id' => ['invalid', 'array'],
      'subdomain' => 'example.com',
    }
    token = generate_jwt_token(payload)

    error = assert_raises(RackJwtAegis::AuthenticationError) do
      validator.validate(token)
    end
    assert_match(/Invalid tenant_id format in JWT payload/, error.message)
  end

  def test_validate_claim_types_valid_tenant_id_formats_with_subdomain
    config = RackJwtAegis::Configuration.new(basic_config.merge(validate_subdomain: true))
    validator = RackJwtAegis::JwtValidator.new(config)

    # Test numeric tenant_id
    payload = {
      'user_id' => 123,
      'tenant_id' => 456,
      'subdomain' => 'example.com',
    }
    token = generate_jwt_token(payload)
    result = validator.validate(token)

    assert_equal 456, result['tenant_id']

    # Test string tenant_id
    payload = {
      'user_id' => 123,
      'tenant_id' => '456',
      'subdomain' => 'example.com',
    }
    token = generate_jwt_token(payload)
    result = validator.validate(token)

    assert_equal '456', result['tenant_id']
  end

  def test_validate_claim_types_invalid_subdomain_format
    config = RackJwtAegis::Configuration.new(basic_config.merge(validate_subdomain: true))
    validator = RackJwtAegis::JwtValidator.new(config)

    payload = {
      'user_id' => 123,
      'tenant_id' => 456,
      'subdomain' => 123, # Should be string
    }
    token = generate_jwt_token(payload)

    error = assert_raises(RackJwtAegis::AuthenticationError) do
      validator.validate(token)
    end
    assert_match(/Invalid subdomain format in JWT payload/, error.message)
  end

  def test_validate_claim_types_invalid_pathname_slugs_format
    config = RackJwtAegis::Configuration.new(basic_config.merge(validate_pathname_slug: true))
    validator = RackJwtAegis::JwtValidator.new(config)

    payload = {
      'user_id' => 123,
      'pathname_slugs' => 'should-be-array',
    }
    token = generate_jwt_token(payload)

    error = assert_raises(RackJwtAegis::AuthenticationError) do
      validator.validate(token)
    end
    assert_match(/Invalid pathname_slugs format in JWT payload - must be array/, error.message)
  end

  def test_validate_claim_types_valid_pathname_slugs_format
    config = RackJwtAegis::Configuration.new(basic_config.merge(validate_pathname_slug: true))
    validator = RackJwtAegis::JwtValidator.new(config)

    payload = {
      'user_id' => 123,
      'pathname_slugs' => ['company-a', 'company-b'],
    }
    token = generate_jwt_token(payload)

    result = validator.validate(token)

    assert_equal ['company-a', 'company-b'], result['pathname_slugs']
  end

  def test_validate_with_custom_payload_mapping
    config = RackJwtAegis::Configuration.new(basic_config.merge(
                                               validate_subdomain: true,
                                               validate_pathname_slug: true,
                                               payload_mapping: {
                                                 user_id: :sub,
                                                 tenant_id: :company_group_id,
                                                 subdomain: :domain,
                                                 pathname_slugs: :accessible_companies,
                                               },
                                             ))
    validator = RackJwtAegis::JwtValidator.new(config)

    payload = {
      'sub' => 123,
      'company_group_id' => 456,
      'domain' => 'example.com',
      'accessible_companies' => ['company-a', 'company-b'],
    }
    token = generate_jwt_token(payload)

    result = validator.validate(token)

    assert_equal 123, result['sub']
    assert_equal 456, result['company_group_id']
    assert_equal 'example.com', result['domain']
    assert_equal ['company-a', 'company-b'], result['accessible_companies']
  end

  def test_validate_successful_basic_payload
    payload = { 'user_id' => 123, 'role' => 'admin' }
    token = generate_jwt_token(payload)

    result = @validator.validate(token)

    assert_equal 123, result['user_id']
    assert_equal 'admin', result['role']
  end

  def test_validate_with_different_jwt_algorithm
    config = RackJwtAegis::Configuration.new(basic_config.merge(jwt_algorithm: 'HS512'))
    validator = RackJwtAegis::JwtValidator.new(config)

    payload = { 'user_id' => 123 }

    # Generate token with HS512
    token = JWT.encode(payload, 'test-secret', 'HS512')

    result = validator.validate(token)

    assert_equal 123, result['user_id']
  end

  def test_validate_standard_error_handling
    # Mock JWT.decode to raise an unexpected error
    JWT.stubs(:decode).raises(RuntimeError.new('Unexpected error'))

    error = assert_raises(RackJwtAegis::AuthenticationError) do
      @validator.validate('any_token')
    end
    assert_match(/JWT validation error: Unexpected error/, error.message)
  end

  def test_jwt_verification_error_specifically
    # Mock JWT.decode to raise JWT::VerificationError directly
    JWT.stubs(:decode).raises(JWT::VerificationError.new('signature verification failed'))

    error = assert_raises(RackJwtAegis::AuthenticationError) do
      @validator.validate('any_token')
    end
    assert_equal 'JWT signature verification failed', error.message
  end

  def test_validate_with_nil_claims_when_not_required
    # Test that nil optional claims don't cause validation errors
    config = RackJwtAegis::Configuration.new(basic_config)
    validator = RackJwtAegis::JwtValidator.new(config)

    payload = {
      'user_id' => 123,
      'optional_field' => nil,
      'another_field' => '',
    }
    token = generate_jwt_token(payload)

    result = validator.validate(token)

    assert_equal 123, result['user_id']
    assert_nil result['optional_field']
    assert_equal '', result['another_field']
  end

  # Additional tests for 100% coverage
  def test_jwt_immature_signature_error
    # Create JWT with nbf (not before) claim set to future
    future_time = Time.now.to_i + 3600
    payload = {
      'user_id' => 123,
      'nbf' => future_time, # Not before - future time
      'exp' => future_time + 3600,
    }

    token = JWT.encode(payload, 'test-secret', 'HS256')

    error = assert_raises(RackJwtAegis::AuthenticationError) do
      @validator.validate(token)
    end

    assert_equal 'JWT token not yet valid', error.message
  end

  def test_jwt_invalid_iat_error
    # Create JWT with iat (issued at) claim set to future
    future_time = Time.now.to_i + 3600
    payload = {
      'user_id' => 123,
      'iat' => future_time, # Issued at - future time (invalid)
      'exp' => future_time + 3600,
    }

    token = JWT.encode(payload, 'test-secret', 'HS256')

    error = assert_raises(RackJwtAegis::AuthenticationError) do
      @validator.validate(token)
    end

    assert_equal 'JWT token issued in the future', error.message
  end

  def test_payload_structure_validation_non_hash
    # Mock JWT.decode to return non-hash payload
    JWT.stubs(:decode).returns(['not-a-hash', {}])

    error = assert_raises(RackJwtAegis::AuthenticationError) do
      @validator.validate('any-token')
    end

    assert_equal 'JWT validation error: Invalid JWT payload structure', error.message
  end
end
