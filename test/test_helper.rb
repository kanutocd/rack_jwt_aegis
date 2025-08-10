# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'rack_jwt_aegis'

require 'minitest/autorun'
require 'minitest/spec'
require 'mocha/minitest'
require 'jwt'
require 'rack'
require 'rack/test'

# Test helper methods
module TestHelpers
  def valid_jwt_payload
    {
      'user_id' => 123,
      'company_group_id' => 456,
      'company_group_domain' => 'acme-corp.example.com',
      'company_slugs' => ['widgets-division', 'services-division'],
      'roles' => ['admin'],
      'exp' => Time.now.to_i + 3600, # 1 hour from now
      'iat' => Time.now.to_i,
    }
  end

  def generate_jwt_token(payload = nil, secret = 'test-secret')
    payload ||= valid_jwt_payload
    JWT.encode(payload, secret, 'HS256')
  end

  def rack_request(method: 'GET', path: '/', host: 'acme-corp.example.com', headers: {})
    env = Rack::MockRequest.env_for(
      "http://#{host}#{path}",
      method: method,
    )

    headers.each do |key, value|
      env["HTTP_#{key.upcase.tr('-', '_')}"] = value
    end

    Rack::Request.new(env)
  end

  def mock_app
    @mock_app ||= ->(_env) { [200, {}, ['OK']] }
  end

  def basic_config
    {
      jwt_secret: 'test-secret',
      debug_mode: false,
    }
  end
end

# Include test helpers in all test classes
class Minitest::Test
  include TestHelpers
end
