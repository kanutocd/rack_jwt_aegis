# Rack JWT Bastion

JWT authentication middleware for hierarchical multi-tenant Rack applications with 2-level tenant support.

**Note: This is version 0.0.0 - a placeholder release to reserve the gem name. Implementation is in progress.**

## Features

- JWT token validation with configurable algorithms
- 2-level multi-tenant support (Company-Group → Company, Organization → Department, etc.)
- Subdomain-based tenant isolation for top-level tenants
- Company slug access control for sub-level tenants
- Configurable path exclusions for public endpoints
- Custom payload validation
- Debug mode for development

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'rack_jwt_bastion'
```

And then execute:

```bash
bundle install
```

Or install it yourself as:

```bash
gem install rack_jwt_bastion
```

## Quick Start

### Rails Application

```ruby
# config/application.rb
config.middleware.insert_before 0, RackJwtBastion::Middleware, {
  jwt_secret: ENV['JWT_SECRET'],
  company_header_name: 'X-Company-Group-Id',
  skip_paths: ['/api/v1/login', '/api/v1/refresh', '/health']
}
```

### Sinatra Application

```ruby
require 'rack_jwt_bastion'

use RackJwtBastion::Middleware, {
  jwt_secret: ENV['JWT_SECRET'],
  company_header_name: 'X-Company-Group-Id',
  skip_paths: ['/login', '/health']
}
```

### Pure Rack Application

```ruby
require 'rack_jwt_bastion'

app = Rack::Builder.new do
  use RackJwtBastion::Middleware, {
    jwt_secret: ENV['JWT_SECRET'],
    validate_subdomain: true,
    validate_company_slug: true
  }

  run YourApp.new
end
```

## Configuration Options

### Basic Configuration

```ruby
RackJwtBastion::Middleware.new(app, {
  # JWT Settings (Required)
  jwt_secret: ENV['JWT_SECRET'],
  jwt_algorithm: 'HS256',  # Default: 'HS256'

  # Multi-Tenant Settings
  company_header_name: 'X-Company-Group-Id',  # Default: 'X-Company-Group-Id'
  validate_subdomain: true,     # Default: false
  validate_company_slug: true,  # Default: false

  # Path Configuration
  skip_paths: ['/health', '/api/v1/login', '/api/v1/refresh'],
  company_slug_pattern: /^\/api\/v1\/([^\/]+)\//,  # Default pattern

  # Response Customization
  unauthorized_response: { error: 'Authentication required' },
  forbidden_response: { error: 'Access denied' },

  # Debugging
  debug_mode: Rails.env.development?  # Default: false
})
```

### Advanced Configuration

```ruby
RackJwtBastion::Middleware.new(app, {
  jwt_secret: ENV['JWT_SECRET'],

  # Custom Payload Validation
  custom_payload_validator: ->(payload, request) {
    # Return true if valid, false if invalid
    payload['role'] == 'admin' || payload['permissions'].include?('read')
  },

  # Flexible Payload Mapping
  payload_mapping: {
    user_id: :sub,                    # Map 'sub' claim to user_id
    company_group_id: :company_id,    # Map 'company_id' claim
    company_group_domain: :domain,    # Map 'domain' claim
    company_slugs: :accessible_companies  # Map array of accessible companies
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

Rack JWT Bastion provides multiple strategies for multi-tenant authentication:

### Subdomain Validation

```ruby
# Validates that the JWT's domain matches the request subdomain
config.validate_subdomain = true
```

### Company Slug Validation

```ruby
# Validates that the requested company slug is accessible to the user
config.validate_company_slug = true
config.company_slug_pattern = /^\/api\/v1\/([^\/]+)\//
```

### Header-Based Validation

```ruby
# Validates the X-Company-Group-Id header against JWT payload
config.company_header_name = 'X-Company-Group-Id'
```

## JWT Payload Structure

The middleware expects JWT payloads with the following structure:

```json
{
  "user_id": 12345,
  "company_group_id": 67890,
  "company_group_domain": "acme.example.com",
  "company_slugs": ["acme", "acme-corp"],
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

Everyone interacting in the Rack JWT Bastion project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](CODE_OF_CONDUCT.md).
