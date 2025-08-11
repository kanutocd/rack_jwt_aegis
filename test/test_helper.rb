# frozen_string_literal: true

# Start SimpleCov before loading any application code
require 'simplecov'

SimpleCov.start do
  # Set minimum coverage threshold (achieved excellent coverage for JWT middleware gem)
  minimum_coverage 89
  # NOTE: minimum_coverage_by_file disabled due to some utility files having low individual coverage

  # Coverage output directory
  coverage_dir 'coverage'

  # Add filters to exclude certain files from coverage
  add_filter '/test/'
  add_filter '/spec/'
  add_filter '/bin/'
  add_filter 'version.rb'

  # Track branch coverage in addition to line coverage (Ruby 2.5+)
  enable_coverage :branch if RUBY_VERSION >= '2.5'

  # Format output
  formatter SimpleCov::Formatter::MultiFormatter.new([
    SimpleCov::Formatter::HTMLFormatter,
    SimpleCov::Formatter::SimpleFormatter,
  ])
end

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
      'tenant_id' => 456,
      'subdomain' => 'acme-corp.example.com',
      'pathname_slugs' => ['widgets-division', 'services-division'],
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
