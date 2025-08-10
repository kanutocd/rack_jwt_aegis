#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../lib/rack_jwt_aegis'
require 'jwt'
require 'json'
require 'rack'

# Example: Basic JWT authentication middleware usage

# 1. Create a simple Rack app
class SimpleApp
  def call(env)
    # Access authenticated user data
    if RackJwtAegis::RequestContext.authenticated?(env)
      user_id = RackJwtAegis::RequestContext.user_id(env)
      company_slugs = RackJwtAegis::RequestContext.company_slugs(env)

      response = {
        message: 'Hello authenticated user!',
        user_id: user_id,
        company_access: company_slugs,
      }

      [200, { 'Content-Type' => 'application/json' }, [JSON.generate(response)]]
    else
      [401, {}, ['Unauthorized']]
    end
  end
end

# 2. Configure the middleware
Rack::Builder.new do
  use RackJwtAegis::Middleware, {
    jwt_secret: 'demo-secret-key',

    # Multi-tenant features
    validate_subdomain: true,
    validate_company_slug: true,

    # Skip authentication for health check
    skip_paths: ['/health'],

    # Debug mode for demonstration
    debug_mode: true,
  }

  run SimpleApp.new
end

# 3. Generate a demo JWT token
payload = {
  'user_id' => 123,
  'company_group_id' => 456,
  'company_group_domain' => 'acme-corp.example.com',
  'company_slugs' => ['widgets-division', 'services-division'],
  'exp' => Time.now.to_i + 3600, # 1 hour from now
}

token = JWT.encode(payload, 'demo-secret-key', 'HS256')

puts "\n🛡️  Rack JWT Aegis Demo"
puts '=' * 50
puts "\n📋 Configuration:"
puts '- JWT Secret: demo-secret-key'
puts '- Multi-tenant: Subdomain + Company Slug validation'
puts '- Skip paths: /health'
puts '- Debug mode: enabled'

puts "\n🎫 Generated JWT Token:"
puts "#{token[0..50]}..." if token.length > 50

puts "\n📊 JWT Payload:"
puts JSON.pretty_generate(payload)

puts "\n✅ Middleware initialized successfully!"
puts "\n💡 To test this middleware:"
puts '1. Start a Rack server with this configuration'
puts '2. Send requests with Authorization: Bearer <token>'
puts '3. Try different subdomains and company slugs'
puts '4. Check /health endpoint (should work without auth)'

puts "\n📝 Example curl commands:"
puts "curl -H 'Authorization: Bearer #{token}' -H 'Host: acme-corp.example.com' http://localhost:3000/api/v1/widgets-division/data"
puts 'curl http://localhost:3000/health'
