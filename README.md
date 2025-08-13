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

```bash
  gem 'rack_jwt_aegis'
```

And then execute:

```bash
  bundle install
```

Or install it yourself as:

```bash
  gem install rack_jwt_aegis
```

## CLI Tool

Rack JWT Aegis includes a command-line tool for generating secure JWT secrets:

```bash
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
```

### Security Features

- Uses `SecureRandom` for cryptographically secure generation
- Default 64-byte secrets provide ~512 bits of entropy
- Multiple output formats: hex, base64, raw
- Environment variable formatting for easy setup

## Quick Start

### Rails Application

```ruby
  # config/application.rb
  config.middleware.insert_before 0, RackJwtAegis::Middleware, {
    jwt_secret: ENV['JWT_SECRET'],
    tenant_id_header_name: 'X-Tenant-Id',
    skip_paths: ['/api/v1/login', '/health']
  }
```

### Sinatra Application

```ruby
  require 'rack_jwt_aegis'

  use RackJwtAegis::Middleware, {
    jwt_secret: ENV['JWT_SECRET'],
    tenant_id_header_name: 'X-Tenant-Id',
    skip_paths: ['/login', '/health']
  }
```

### Pure Rack Application

```ruby
  require 'rack_jwt_aegis'

  app = Rack::Builder.new do
    use RackJwtAegis::Middleware, {
      jwt_secret: ENV['JWT_SECRET'],
      validate_subdomain: true,
      validate_pathname_slug: true
    }

    run YourApp.new
  end
```

## Configuration Options

### Basic Configuration

```ruby
RackJwtAegis::Middleware.new(app, {
  # JWT Settings (Required)
  jwt_secret: ENV['JWT_SECRET'],
  jwt_algorithm: 'HS256',  # Default: 'HS256'

  # Multi-Tenant Settings
  tenant_id_header_name: 'X-Tenant-Id',  # Default: 'X-Tenant-Id'
  validate_subdomain: true,     # Default: false
  validate_pathname_slug: true,  # Default: false

  # Path Configuration
  skip_paths: ['/health', '/api/v1/login'],
  pathname_slug_pattern: /^\/api\/v1\/([^\/]+)\//,  # Default pattern

  # RBAC Configuration
  rbac_enabled: true,               # Default: false
  rbac_cache_store: :redis,         # Required when RBAC enabled
  rbac_cache_options: { url: ENV['REDIS_URL'] },
  user_permissions_ttl: 3600,       # Default: 1800 (30 minutes) - TTL for cached user permissions

  # Cache Store Configuration (choose one approach)
  # Option 1: Shared cache for both RBAC and permissions
  cache_store: :memory,             # :memory, :redis, :memcached, :solid_cache
  cache_options: { url: ENV['REDIS_URL'] },

  # Option 2: Separate cache stores for RBAC and permissions
  rbac_cache_store: :redis,         # For RBAC permissions data
  rbac_cache_options: { url: ENV['REDIS_URL'] },
  permission_cache_store: :memory,  # For cached user permissions
  permission_cache_options: {},

  # Response Customization
  unauthorized_response: { error: 'Authentication required' },
  forbidden_response: { error: 'Access denied' },

  # Debugging
  debug_mode: Rails.env.development?  # Default: false
})
```

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

## Request Context Access

After successful JWT authentication, the middleware stores user context in the Rack environment for easy access in your application:

### Basic Usage

```ruby
# In your controllers or middleware
class UsersController < ApplicationController
  def index
    # Check if request is authenticated
    return unauthorized unless RackJwtAegis::RequestContext.authenticated?(request.env)

    # Get user information
    user_id = RackJwtAegis::RequestContext.user_id(request.env)
    tenant_id = RackJwtAegis::RequestContext.tenant_id(request.env)

    # Access full JWT payload
    payload = RackJwtAegis::RequestContext.payload(request.env)
    roles = payload['roles']

    # Your business logic here
    users = User.where(tenant_id: tenant_id)
    render json: users
  end
end
```

### Multi-Tenant Context

```ruby
# Access subdomain information
subdomain = RackJwtAegis::RequestContext.subdomain(request.env)
# => "acme-group-of-companies"

# Check pathname slug access
accessible_companies = RackJwtAegis::RequestContext.pathname_slugs(request.env)
# => ["company-a", "company-b"]

# Check if user has access to specific company
has_access = RackJwtAegis::RequestContext.has_company_access?(request.env, "company-a")
# => true

# Helper methods for request objects
user_id = RackJwtAegis::RequestContext.current_user_id(request)
tenant_id = RackJwtAegis::RequestContext.current_tenant_id(request)
```

### Available Context Methods

- `authenticated?(env)` - Check if request is authenticated
- `payload(env)` - Get full JWT payload hash
- `user_id(env)` - Get authenticated user ID
- `tenant_id(env)` - Get tenant/company group ID
- `subdomain(env)` - Get subdomain from JWT
- `pathname_slugs(env)` - Get array of accessible company slugs
- `current_user_id(request)` - Helper for request objects
- `current_tenant_id(request)` - Helper for request objects
- `has_company_access?(env, slug)` - Check company access

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

## Performance & Caching

- Skip paths are checked before JWT processing
- Low memory footprint
- Multi-tier permission caching system for RBAC performance
- TTL-based cache invalidation for user permissions
- Support for multiple cache stores: `:memory`, `:redis`, `:memcached`, `:solid_cache`

### Cache Store Configuration

#### Supported Cache Stores

1. **Memory Cache** (`:memory`) - For development and testing
2. **Redis Cache** (`:redis`) - For production with high availability
3. **Memcached Cache** (`:memcached`) - For distributed caching
4. **Solid Cache** (`:solid_cache`) - For Rails 8+ applications

#### Configuration Examples

```ruby
# Memory cache (development/testing)
config.cache_store = :memory

# Redis cache
config.cache_store = :redis
config.cache_options = { url: ENV['REDIS_URL'] }

# Memcached cache
config.cache_store = :memcached
config.cache_options = { servers: ['localhost:11211'] }

# Solid Cache (Rails 8+)
config.cache_store = :solid_cache
```

#### Separate Cache Stores

You can configure separate cache stores for RBAC permissions data and cached user permissions:

```ruby
# Use Redis for RBAC data (shared across instances)
config.rbac_cache_store = :redis
config.rbac_cache_options = { url: ENV['REDIS_URL'] }

# Use memory for user permission cache (faster local access)
config.permission_cache_store = :memory
config.permission_cache_options = {}
```

## RBAC Cache Format

When RBAC is enabled, the middleware expects permissions to be stored in the cache with this exact format:

```json
{
  "last_update": 1640995200,
  "permissions": [
    {
      "123": [
        "sales/invoices:get",
        "sales/invoices:post",
        "%r{sales/invoices/\\d+}:get",
        "%r{sales/invoices/\\d+}:put",
        "users/*:get"
      ]
    },
    {
      "456": ["admin/*:*", "reports:get"]
    }
  ]
}
```

### Format Specification

- **last_update**: Timestamp for cache invalidation
- **permissions**: Array of role permission objects
- **Role ID**: String or numeric identifier for user roles
- **Permission Format**: `"resource-endpoint:http-method"`
  - **resource-endpoint**: API path (literal string or regex pattern)
  - **http-method**: `get`, `post`, `put`, `delete`, or `*` (wildcard)

### Permission Examples

```ruby
# Literal path matching
"sales/invoices:get"        # GET /api/v1/company/sales/invoices
"users/profile:put"         # PUT /api/v1/company/users/profile

# Regex pattern matching
"%r{ sales/invoices/\\d+}:get"    # GET /api/v1/company/sales/invoices/123
"%r{ users/\\d+/orders}:*"        # Any method on /api/v1/company/users/123/orders

# Wildcard method
"reports:*"                 # Any method on reports endpoint
"admin/*:*"                 # Full admin access
```

### Request Authorization Flow

1. **Check User Permissions Cache**: Fast lookup in middleware cache

   - **RBAC Update Check**: If RBAC permissions updated within TTL → **Nuke entire cache**
   - **TTL Check**: If individual permission older than configured TTL → Remove only that permission
   - If cache valid and permission found: **✅ Authorized**
   - If cache valid but no permission: **❌ 403 Forbidden**

2. **RBAC Permissions Validation**: Full permission evaluation

   - Extract user roles from JWT payload (`roles`, `role`, `user_roles`, or `role_ids` field)
   - Load RBAC permissions collection and validate format
   - For each user role, check if any permission matches:
     - Extract resource path from request URL (removes subdomain/pathname slug)
     - Match against permission patterns (literal or regex)
     - Validate HTTP method (exact match or wildcard)
   - If authorized: Cache permission for future requests
   - Return 403 Forbidden if no matching permissions found

3. **Cache Storage**: Successful permissions cached with simple key-value format:
   ```json
   {
     "12345:acme-group.localhost.local/api/v1/company/sales/invoices:get": 1640995200,
     "12345:acme-group.localhost.local/api/v1/company/sales/invoices:post": 1640995200
   }
   ```
   TTL configurable via `user_permissions_ttl` option (default: 30 minutes)

### Cache Invalidation Strategy

**RBAC Collection Updated** (e.g., role permissions changed):

- **Condition**: RBAC `last_update` within configured TTL
- **Action**: **Nuke entire cache** (all users, all permissions)
- **Reason**: Any permission could have changed, safer to re-evaluate everything

**Individual Permission TTL Expired**:

- **Condition**: Specific permission older than configured TTL
- **Action**: **Remove only that permission** (preserve others)
- **Reason**: Permission naturally aged out, other permissions still valid

### Example Authorization

Request: `POST https://acme-group.localhost/api/v1/an-acme-company/sales/invoices`

- User has role: `123`
- Role `123` permissions: `["sales/invoices:get", "sales/invoices:post"]`
- Extracted resource path: `sales/invoices`
- Request method: `POST`
- Result: **✅ Authorized** (matches `sales/invoices:post`)

Request: `DELETE https://acme-group.localhost/api/v1/an-acme-company/sales/invoices/456`

- User has role: `123`
- Role `123` permissions: `["sales/invoices:get", "%r{sales/invoices/\\d+}:put"]`
- Extracted resource path: `sales/invoices/456`
- Request method: `DELETE`
- Result: **❌ 403 Forbidden** (no DELETE permission)

## Error Handling

The middleware returns appropriate HTTP status codes:

- **401 Unauthorized** - Missing, invalid, or expired JWT
- **403 Forbidden** - Valid JWT but insufficient permissions/access

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`.

## Contributing

Bug reports and pull requests are welcome on GitHub. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Rack JWT Aegis project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](CODE_OF_CONDUCT.md).
