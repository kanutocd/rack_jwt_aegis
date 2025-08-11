# Rack JWT Aegis

JWT authentication middleware for hierarchical multi-tenant Rack applications with 2-level tenant support.

## Features

- JWT token validation with configurable algorithms
- 2-level multi-tenant support (Example: Company-Group → Company, Organization → Department, etc.)
- Subdomain-based tenant isolation for top-level tenants
- URL pathname slug access control for sub-level tenants
- Configurable path exclusions for public endpoints
- Custom payload validation
- Debug mode for development

## Installation

Add this line to your application's Gemfile:

    gem 'rack_jwt_aegis'

And then execute:

    bundle install

Or install it yourself as:

    gem install rack_jwt_aegis

## CLI Tool

Rack JWT Aegis includes a command-line tool for generating secure JWT secrets:

    # Generate a secure JWT secret
    rack-jwt-aegis secret
    
    # Generate base64-encoded secret
    rack-jwt-aegis secret --format base64
    
    # Generate secret in environment variable format
    rack-jwt-aegis secret --env
    
    # Generate multiple secrets
    rack-jwt-aegis secret --count 3
    
    # Quiet mode (secret only)
    rack-jwt-aegis secret --quiet
    
    # Custom length (32 bytes)
    rack-jwt-aegis secret --length 32
    
    # Show help
    rack-jwt-aegis --help

### Security Features

- Uses `SecureRandom` for cryptographically secure generation
- Default 64-byte secrets provide ~512 bits of entropy
- Multiple output formats: hex, base64, raw
- Environment variable formatting for easy setup

## Quick Start

### Rails Application

    # config/application.rb
    config.middleware.insert_before 0, RackJwtAegis::Middleware, {
      jwt_secret: ENV['JWT_SECRET'],
      tenant_id_header_name: 'X-Tenant-Id',
      skip_paths: ['/api/v1/login', '/api/v1/refresh', '/health']
    }

### Sinatra Application

    require 'rack_jwt_aegis'
    
    use RackJwtAegis::Middleware, {
      jwt_secret: ENV['JWT_SECRET'],
      tenant_id_header_name: 'X-Tenant-Id',
      skip_paths: ['/login', '/health']
    }

### Pure Rack Application

    require 'rack_jwt_aegis'
    
    app = Rack::Builder.new do
      use RackJwtAegis::Middleware, {
        jwt_secret: ENV['JWT_SECRET'],
        validate_subdomain: true,
        validate_pathname_slug: true
      }
    
      run YourApp.new
    end

## Configuration Options

### Basic Configuration

    RackJwtAegis::Middleware.new(app, {
      # JWT Settings (Required)
      jwt_secret: ENV['JWT_SECRET'],
      jwt_algorithm: 'HS256',  # Default: 'HS256'
    
      # Multi-Tenant Settings
      tenant_id_header_name: 'X-Tenant-Id',  # Default: 'X-Tenant-Id'
      validate_subdomain: true,     # Default: false
      validate_pathname_slug: true,  # Default: false
    
      # Path Configuration
      skip_paths: ['/health', '/api/v1/login', '/api/v1/refresh'],
      pathname_slug_pattern: /^\/api\/v1\/([^\/]+)\//,  # Default pattern
    
      # Response Customization
      unauthorized_response: { error: 'Authentication required' },
      forbidden_response: { error: 'Access denied' },
    
      # Debugging
      debug_mode: Rails.env.development?  # Default: false
    })

### Advanced Configuration

```ruby
RackJwtAegis::Middleware.new(app, {
  jwt_secret: ENV['JWT_SECRET'],

  # Custom Payload Validation
  custom_payload_validator: ->(payload, request) {
    # Return true if valid, false if invalid
    payload['role'] == 'admin' || payload['permissions'].include?('read')
  },

  # Flexible Payload Mapping
  payload_mapping: {
    user_id: :sub,                    # Map 'sub' claim to user_id
    tenant_id: :company_group_id,    # Map 'company_group_id' claim
    subdomain: :company_group_domain_name,    # Map 'company_group_domain_name' claim
    pathname_slugs: :accessible_company_slugs  # Map array of accessible companies
  },

  # Custom Tenant Extraction
  tenant_strategy: :custom,
  tenant_extractor: ->(request) {
    # Extract tenant from custom header or logic
    request.get_header('HTTP_X_TENANT_ID')
  }
})
```

## Multi-Tenant Support

Rack JWT Aegis provides multiple strategies for multi-tenant authentication:

### Subdomain Validation

```ruby
# Validates that the JWT's domain matches the request subdomain
config.validate_subdomain = true
```

### Company Slug Validation

```ruby
# Validates that the requested company slug is accessible to the user
config.validate_pathname_slug = true
config.pathname_slug_pattern = /^\/api\/v1\/([^\/]+)\//
```

### Header-Based Validation

```ruby
# Validates the X-Tenant-Id header against JWT payload
config.tenant_id_header_name = 'X-Tenant-Id'
```

The value from this request header entry will be used to verify the JWT's mapped `tenant_id` claim.

## JWT Payload Structure

The middleware expects JWT payloads with the following structure:

```json
{
  "user_id": 12345,
  "tenant_id": 67890,
  "subdomain": "acme-group-of-companies", # the subdomain part of the host of the request url, e.g. `http://acme-group-of-companies.example.com`
  "pathname_slugs": ["an-acme-company-subsidiary", "another-acme-company-the-user-has-access"], # the user has access to these kind of request urls: https://acme-group-of-companies.example.com/api/v1/an-acme-company-subsidiary/* or https://acme-group-of-companies.example.com/api/v1/another-acme-company-the-user-has-access/
  "roles": ["admin", "user"],
  "exp": 1640995200,
  "iat": 1640991600
}
```

You can customize the payload mapping using the `payload_mapping` configuration option.

## Security Features

- JWT signature verification
- Token expiration validation
- Company/tenant access control
- Subdomain validation
- Request path filtering for public endpoints

## Performance

- Skip paths are checked before JWT processing
- Low memory footprint

## Error Handling

The middleware returns appropriate HTTP status codes:

- **401 Unauthorized** - Missing, invalid, or expired JWT
- **403 Forbidden** - Valid JWT but insufficient permissions/access

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Rack JWT Aegis project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](CODE_OF_CONDUCT.md).
