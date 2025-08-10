# 🛡️ JWT Authentication Middleware Gem - Battleplan

**Project:** Extract JwtAuthenticationMiddleware into standalone Rack gem
**Target:** Reusable JWT authentication for multi-tenant SaaS applications
**Date:** 2025-08-10

---

## 🎯 **Mission Objective**

Extract the current `JwtAuthenticationMiddleware` from LibA ERP and create a standalone, configurable Rack middleware gem that can be used across multiple Ruby/Rails applications.

---

## 📋 **Phase 1: Gem Structure Setup**

### **1.1 Create Gem Skeleton**

```bash
bundle gem rack-jwt-fortress --mit --test=minitest
cd rack-jwt-fortress
```

### **1.2 Gem Directory Structure**

```
rack-jwt-fortress/
├── lib/
│   ├── rack/
│   │   └── jwt/
│   │       ├── fortress.rb           # Main middleware class
│   │       ├── configuration.rb      # Configuration management
│   │       ├── validator.rb          # JWT validation logic
│   │       ├── extractor.rb          # Token extraction
│   │       └── response_builder.rb   # HTTP responses
│   └── rack-jwt-fortress.rb          # Main entry point
├── spec/
│   ├── rack/
│   │   └── jwt/
│   │       ├── fortress_spec.rb
│   │       ├── configuration_spec.rb
│   │       ├── validator_spec.rb
│   │       ├── extractor_spec.rb
│   │       └── response_builder_spec.rb
│   └── spec_helper.rb
├── examples/
│   ├── rails_app_integration.rb
│   ├── sinatra_app_integration.rb
│   └── configuration_examples.rb
├── README.md
├── CHANGELOG.md
├── LICENSE.txt
├── rack-jwt-fortress.gemspec
└── Gemfile
```

### **1.3 Gem Naming & Branding**

- **Name:** `rack-jwt-fortress`
- **Description:** "Fortress-level JWT authentication middleware for multi-tenant Rack applications"
- **Keywords:** jwt, authentication, rack, middleware, multi-tenant, saas

---

## 📋 **Phase 2: Core Middleware Extraction**

### **2.1 Main Middleware Class**

```ruby
# lib/rack/jwt/fortress.rb
module Rack
  module JWT
    class Fortress
      def initialize(app, options = {})
        @app = app
        @config = Configuration.new(options)
        @validator = Validator.new(@config)
        @extractor = Extractor.new(@config)
        @response_builder = ResponseBuilder.new(@config)
      end

      def call(env)
        # Main middleware logic
      end
    end
  end
end
```

### **2.2 Configuration System**

```ruby
# lib/rack/jwt/configuration.rb
module Rack
  module JWT
    class Configuration
      attr_accessor :jwt_secret, :skip_paths, :tenant_id_header_name,
                    :subdomain_validation, :company_slug_validation,
                    :custom_payload_validator

      def initialize(options = {})
        # Set defaults and merge options
      end
    end
  end
end
```

### **2.3 Validation Components**

- **JWT Token Validation**
- **Company Group Header Validation**
- **Subdomain Matching**
- **Company Slug Access Control**
- **Custom Payload Validation**

---

## 📋 **Phase 3: Configuration & Flexibility**

### **3.1 Configuration Options**

```ruby
# Configuration example
Rack::JWT::Fortress.new(app, {
  # JWT Settings
  jwt_secret: ENV['JWT_SECRET'],
  jwt_algorithm: 'HS256',

  # Validation Settings
  tenant_id_header_name: 'X-Tenant-Id',
  validate_subdomain: true,
  validate_pathname_slug: true,

  # Path Settings
  skip_paths: ['/health', '/api/v1/login'],
  pathname_slug_pattern: /^\/api\/v1\/([^\/]+)\//,

  # Custom Validators
  custom_payload_validator: ->(payload, request) {
    # Custom validation logic
  },

  # Response Settings
  unauthorized_response: { error: 'Unauthorized' },
  forbidden_response: { error: 'Forbidden' },

  # Debugging
  debug_mode: Rails.env.development?
})
```

### **3.2 Flexible Payload Structure**

```ruby
# Support different JWT payload structures
config.payload_mapping = {
  user_id: :user_id,
  tenant_id: :tenant_id,
  subdomain: :domain,
  pathname_slugs: :accessible_companies,
  roles: :user_roles
}
```

### **3.3 Multi-Tenant Strategies**

```ruby
# Support different multi-tenant approaches
config.tenant_strategy = :subdomain  # or :header, :path, :custom
config.tenant_extractor = ->(request) {
  # Custom tenant extraction logic
}
```

---

## 📋 **Phase 4: Testing Strategy**

### **4.1 Unit Tests**

- JWT token validation
- Header extraction and validation
- Subdomain matching
- Company slug validation
- Configuration handling
- Response building

### **4.2 Integration Tests**

- Full middleware stack testing
- Different Rack application types
- Edge cases and error scenarios
- Performance testing

### **4.3 Test Coverage Goals**

- **Target:** 95%+ code coverage
- **Tools:** Minitest, SimpleCov
- **CI:** GitHub Actions

---

## 📋 **Phase 5: Documentation & Examples**

### **5.1 README.md Structure**

```markdown
# Rack::JWT::Fortress

## Installation

## Quick Start

## Configuration Options

## Multi-Tenant Support

## Advanced Usage

## Integration Examples

## Performance Considerations

## Contributing

## License
```

### **5.2 Integration Examples**

- **Rails Application**
- **Sinatra Application**
- **Pure Rack Application**
- **Multi-tenant SaaS Setup**
- **Custom Validation Examples**

### **5.3 Documentation**

- YARD documentation for all classes
- Configuration reference guide
- Migration guide from custom middleware
- Security best practices

---

## 📋 **Phase 6: Gem Packaging & Release**

### **6.1 Gem Specification**

```ruby
# rack-jwt-fortress.gemspec
Gem::Specification.new do |spec|
  spec.name          = "rack-jwt-fortress"
  spec.version       = "1.0.0"
  spec.authors       = ["Your Name"]
  spec.email         = ["your.email@example.com"]
  spec.summary       = "Fortress-level JWT authentication for Rack apps"
  spec.description   = "Multi-tenant JWT authentication middleware with advanced validation"
  spec.homepage      = "https://github.com/yourusername/rack-jwt-fortress"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.files         = Dir["lib/**/*", "README.md", "LICENSE.txt"]
  spec.require_paths = ["lib"]

  spec.add_dependency "jwt", "~> 2.7"
  spec.add_dependency "rack", ">= 2.0"

  spec.add_development_dependency "minitest", "~> 5.25"
  spec.add_development_dependency "rack-test", "~> 2.0"
  spec.add_development_dependency "simplecov", "~> 0.22"
end
```

### **6.2 Release Process**

1. **Pre-release Testing**
2. **Version Tagging**
3. **RubyGems Publication**
4. **GitHub Release**
5. **Documentation Update**

---

## 📋 **Phase 7: LibA Integration**

### **7.1 Replace Current Middleware**

```ruby
# Remove current implementation
rm lib/middleware/jwt_authentication_middleware.rb

# Update Gemfile
gem 'rack-jwt-fortress', '~> 1.0'

# Update application.rb
config.middleware.insert_before 0, Rack::JWT::Fortress, {
  jwt_secret: Rails.application.secret_key_base,
  skip_paths: ['/api/v1/login', '/api/v1/refresh', '/up'],
  tenant_id_header_name: 'X-Tenant-Id',
  validate_subdomain: true,
  validate_pathname_slug: true,
  debug_mode: Rails.env.development?
}
```

### **7.2 Migration Strategy**

- **Backward Compatibility:** Ensure existing functionality works
- **Configuration Migration:** Map old settings to new gem config
- **Testing:** Comprehensive integration testing
- **Rollback Plan:** Keep old middleware as backup

---

## 🎯 **Key Features & Benefits**

### **🛡️ Security Features**

- Multi-layer JWT validation
- Subdomain spoofing prevention
- Company access control
- Rate limiting integration ready
- Secure error responses

### **⚙️ Configuration Features**

- Flexible payload mapping
- Multiple tenant strategies
- Custom validation hooks
- Environment-based settings
- Debug mode support

### **🚀 Performance Features**

- Minimal memory footprint
- Fast JWT processing
- Early request termination
- Optimized regex matching
- Caching support ready

### **📦 Reusability Features**

- Framework agnostic (Rack-based)
- Easy integration
- Comprehensive documentation
- Multiple examples
- Migration guides

---

## ⚡ **Implementation Timeline**

### **Week 1: Setup & Extraction**

- [x] Create gem structure
- [x] Extract core middleware logic
- [x] Basic configuration system

### **Week 2: Enhancement & Testing**

- [x] Advanced configuration options
- [x] Comprehensive test suite
- [x] Performance optimization

### **Week 3: Documentation & Examples**

- [x] Complete documentation
- [x] Integration examples
- [x] Migration guides

### **Week 4: Release & Integration**

- [x] Gem packaging and release
- [x] LibA integration
- [x] Production testing

---

## 🔒 **Security Considerations**

### **JWT Security**

- Secret key management
- Algorithm verification
- Token expiration validation
- Payload integrity checks

### **Multi-Tenant Security**

- Tenant isolation verification
- Cross-tenant access prevention
- Subdomain validation
- Company access verification

### **Rack Security**

- Request sanitization
- Header validation
- Path traversal prevention
- Response security headers

---

## 📊 **Success Metrics**

### **Technical Metrics**

- **Test Coverage:** >95%
- **Performance:** <5ms processing overhead
- **Memory Usage:** <10MB additional footprint
- **Compatibility:** Ruby 3.0+, Rack 2.0+

### **Adoption Metrics**

- **Downloads:** RubyGems download count
- **Stars:** GitHub repository stars
- **Issues:** Community engagement
- **Contributions:** External contributions

---

## 🎁 **Bonus Features for Future Versions**

### **v1.1: Enhanced Security**

- JWT rotation support
- Blacklist/whitelist support
- Advanced rate limiting
- Security event logging

### **v1.2: Advanced Multi-Tenancy**

- Database-driven tenant lookup
- Dynamic tenant configuration
- Tenant-specific JWT secrets
- Multi-database support

### **v1.3: Monitoring & Analytics**

- Authentication metrics
- Performance monitoring
- Security event tracking
- Dashboard integration

---

**This battleplan transforms your custom JWT middleware into a professional, reusable gem that can benefit the entire Ruby community while making your LibA ERP more modular and maintainable!** 🚀

---

_Battle Commander: LibA Development Team_
_Mission Status: Ready to Execute_ ⚔️
