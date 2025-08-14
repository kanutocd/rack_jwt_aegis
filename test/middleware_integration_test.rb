# frozen_string_literal: true

require 'test_helper'
require 'rack/test'

class MiddlewareIntegrationTest < Minitest::Test
  include Rack::Test::Methods

  def app
    @app ||= Rack::Builder.new do
      use RackJwtAegis::Middleware, {
        jwt_secret: 'test-secret',
        skip_paths: ['/health'],
      }

      run ->(env) {
        user_id = RackJwtAegis::RequestContext.user_id(env)
        [200, { 'Content-Type' => 'application/json' }, [JSON.generate({ user_id: user_id })]]
      }
    end
  end

  def test_allows_skip_paths_without_auth
    get '/health'

    assert_equal 200, last_response.status
  end

  def test_requires_authorization_header
    get '/api/users'

    assert_equal 401, last_response.status

    response = JSON.parse(last_response.body)

    assert_match(/authorization header missing/i, response['error'])
  end

  def test_validates_bearer_token_format
    header 'Authorization', 'Invalid format'
    get '/api/users'

    assert_equal 401, last_response.status
    response = JSON.parse(last_response.body)

    assert_match(/invalid authorization header format/i, response['error'])
  end

  def test_error_message_with_gem_information_in_debug_mode
    @app = Rack::Builder.new do
      use RackJwtAegis::Middleware, {
        jwt_secret: 'test-secret',
        validate_pathname_slug: true,
        debug_mode: true,
      }

      run ->(_env) { [200, {}, ['OK']] }
    end
    header 'Authorization', 'Invalid format'
    get '/api/users'

    assert_equal 401, last_response.status
    response = JSON.parse(last_response.body)

    assert_equal 'rack_jwt_aegis', response['middleware']
    assert response.key?('version'), 'Response contains the middle version information'
  end

  def test_successful_authentication_and_context_setting
    token = generate_jwt_token
    header 'Authorization', "Bearer #{token}"

    get '/api/users'

    assert_equal 200, last_response.status

    response = JSON.parse(last_response.body)

    assert_equal 123, response['user_id']
  end

  def test_rejects_expired_tokens
    expired_payload = valid_jwt_payload.merge('exp' => Time.now.to_i - 3600)
    token = generate_jwt_token(expired_payload)

    header 'Authorization', "Bearer #{token}"
    get '/api/users'

    assert_equal 401, last_response.status
    response = JSON.parse(last_response.body)

    assert_match(/expired/, response['error'])
  end

  def test_multi_tenant_subdomain_validation
    @app = Rack::Builder.new do
      use RackJwtAegis::Middleware, {
        jwt_secret: 'test-secret',
        validate_subdomain: true,
      }

      run ->(_env) { [200, {}, ['OK']] }
    end

    token = generate_jwt_token
    header 'Authorization', "Bearer #{token}"
    header 'Host', 'wrong-subdomain.example.com'

    get '/api/users'

    assert_equal 403, last_response.status

    response = JSON.parse(last_response.body)

    assert_match(/subdomain access denied/i, response['error'])
  end

  def test_multi_tenant_company_slug_validation
    @app = Rack::Builder.new do
      use RackJwtAegis::Middleware, {
        jwt_secret: 'test-secret',
        validate_pathname_slug: true,
      }

      run ->(_env) { [200, {}, ['OK']] }
    end

    token = generate_jwt_token
    header 'Authorization', "Bearer #{token}"

    # Try accessing company not in user's accessible list
    get '/api/v1/unauthorized-company/data'

    assert_equal 403, last_response.status

    response = JSON.parse(last_response.body)

    assert_match(/Pathname slug access denied/i, response['error'])

    # Try accessing allowed company
    get '/api/v1/widgets-division/data'

    assert_equal 200, last_response.status
  end

  private

  def header(name, value)
    @headers ||= {}
    @headers["HTTP_#{name.upcase.tr('-', '_')}"] = value
  end

  attr_reader :last_request, :last_response

  def get(path, params = {}, env = {})
    env.merge!(@headers) if @headers
    @last_request = Rack::MockRequest.new(app)
    @last_response = @last_request.get(path, params.merge(env))
  end
end
