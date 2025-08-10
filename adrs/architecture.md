# ADR: Rack JWT Bastion - Complete Architecture Design

**Status:** Proposed
**Date:** 2025-08-10
**Project:** rack_jwt_bastion
**Version:** 0.0.0

---

## Executive Summary

Rack JWT Bastion is a modular JWT authentication middleware for hierarchical multi-tenant Rack applications. It supports 2-level tenant hierarchies (e.g., Company-Group → Company, Organization → Department, Company → Project) with configurable authentication layers from basic JWT validation to advanced Role-Based Access Control (RBAC), flexible caching strategies, and security-first design principles.

---

## Problem Statement

Existing JWT authentication middleware gems for Ruby/Rack applications lack integrated hierarchical multi-tenant support and granular access control. Current solutions require combining multiple gems (jwt authentication + multi-tenancy + RBAC) with complex configurations and potential security gaps between components.

**Key Gaps Identified:**

- No single gem provides JWT + hierarchical multi-tenant + RBAC functionality
- Existing solutions don't support 2-level tenant hierarchies (Company-Group → Company)
- No built-in subdomain isolation security for nested tenant structures
- Limited flexibility in permission caching strategies for complex tenant relationships
- No consideration for trust boundaries between middleware and applications

---

## Architecture Overview

### Core Design Principles

1. **Modularity** - All features except basic JWT validation are optional and configurable
2. **Security-First** - Respects trust boundaries between middleware and host applications
3. **Performance** - Multi-layer caching with minimal request overhead
4. **Flexibility** - Supports multiple deployment scenarios and cache backends

### System Components

```
┌─────────────────────────────────────────────────────────────────┐
│                        HTTP REQUEST                             │
│                    (with JWT token)                             │
└─────────────────────┬───────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────────┐
│               JWT Bastion Middleware                            │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                Request Flow                             │    │
│  │                                                         │    │
│  │  1. Skip Path Check          → Skip if public          │    │
│  │  2. JWT Token Extraction     → Authorization header    │    │
│  │  3. JWT Validation           → Signature & expiration  │    │
│  │  4. Subdomain Validation     → [Optional] Match domain │    │
│  │  5. Company Slug Validation  → [Optional] Path access  │    │
│  │  6. RBAC Permission Check    → [Optional] Role access  │    │
│  │  7. Set Request Context      → Add user data to env    │    │
│  └─────────────────────────────────────────────────────────┘    │
│                              │                                  │
│                              ▼                                  │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │              Component Architecture                     │    │
│  │                                                         │    │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐     │    │
│  │  │   Token     │  │    Multi-   │  │    RBAC     │     │    │
│  │  │ Validator   │  │   Tenant    │  │  Manager    │     │    │
│  │  │             │  │ Validator   │  │             │     │    │
│  │  │ • JWT sig   │  │ • Subdomain │  │ • Permission│     │    │
│  │  │ • Exp check │  │ • Company   │  │   lookup    │     │    │
│  │  │ • Algorithm │  │   headers   │  │ • Cache mgmt│     │    │
│  │  │   verify    │  │ • Path slug │  │ • Timestamp │     │    │
│  │  └─────────────┘  │   matching  │  │   validation│     │    │
│  │                   └─────────────┘  └─────────────┘     │    │
│  └─────────────────────────────────────────────────────────┘    │
└─────────────────────┬───────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────────┐
│                 Rack Application                                │
│                                                                 │
│  • Receives authenticated request with user context            │
│  • Manages RBAC data in cache (when RBAC enabled)              │
│  • Controls middleware trust level and cache access            │
└─────────────────────────────────────────────────────────────────┘
```

---

## Feature Architecture

### 1. Basic JWT Verification (Always Enabled)

**Purpose:** Core JWT token validation
**Dependencies:** ruby-jwt gem
**Process:**

- Extract JWT from Authorization header (Bearer token)
- Validate signature against configured secret/key
- Verify expiration (exp) and not-before (nbf) claims
- Support multiple algorithms: HS256, HS384, HS512, RS256, RS384, RS512

```ruby
# Configuration
{
  jwt_secret: ENV['JWT_SECRET'],
  jwt_algorithm: 'HS256',  # Default
  skip_paths: ['/health', '/login']
}
```

### 2. Subdomain Isolation Validation (Optional)

**Purpose:** Prevent cross-tenant access via subdomain spoofing
**Security Model:** Validates JWT domain claim matches request subdomain

**Process:**

- Extract subdomain from request host
- Compare against JWT payload `company_group_domain`
- Reject requests where subdomain doesn't match JWT tenant

```ruby
# Configuration
{
  validate_subdomain: true,
  payload_mapping: {
    company_group_domain: :domain  # JWT claim mapping
  }
}
```

### 3. Company Slug Validation (Optional)

**Purpose:** Path-based tenant access control
**Security Model:** Ensures user can only access permitted company paths

**Process:**

- Extract company slug from URL path using regex pattern
- Compare against JWT payload `company_slugs` array
- Reject if requested company not in user's accessible list

```ruby
# Configuration
{
  validate_company_slug: true,
  company_slug_pattern: /^\/api\/v1\/([^\/]+)\//,
  payload_mapping: {
    company_slugs: :accessible_companies
  }
}
```

### 4. Role-Based Access Control (Optional)

**Purpose:** Fine-grained permission control per endpoint and HTTP method
**Security Model:** Two-layer caching with configurable trust boundaries

#### RBAC Architecture Components

**Permission Structure:**

```
{user-identity}:{url-host}:{url-pathname}:{http-method} → boolean
```

**Cache Invalidation:**

```
{last-update}:{unix-timestamp} → application responsibility
```

#### Two-Mode Caching System

**Mode 1: Shared Cache (High Trust)**

```
Application ←→ Shared Cache Store ←→ Middleware
            (both read/write)
```

**Mode 2: Isolated Caches (Zero Trust)**

```
Application → RBAC Cache → Middleware (read-only)
Middleware → Permission Cache (read/write)
```

---

## Security Architecture

### Trust Boundaries

```
┌─────────────────────────────────────────────────────────────┐
│                    Security Zones                           │
│                                                             │
│  ┌─────────────────┐    ┌─────────────────┐                │
│  │   Application   │    │   Middleware    │                │
│  │     Zone        │    │     Zone        │                │
│  │                 │    │                 │                │
│  │ • RBAC Master   │───▶│ • JWT Validation│                │
│  │   Data          │    │ • Permission    │                │
│  │ • User Mgmt     │    │   Checking      │                │
│  │ • Role Assignment│    │ • Request       │                │
│  │                 │    │   Authorization │                │
│  │ TRUSTED         │    │                 │                │
│  └─────────────────┘    │ MAY BE          │                │
│                         │ UNTRUSTED       │                │
│                         └─────────────────┘                │
└─────────────────────────────────────────────────────────────┘
```

### Security Features

1. **JWT Signature Verification** - Prevents token tampering
2. **Expiration Validation** - Automatic token lifecycle management
3. **Subdomain Isolation** - Prevents tenant hopping attacks
4. **Company Access Control** - Path-based authorization
5. **RBAC Permission Checking** - Method-level access control
6. **Cache Isolation Options** - Protects critical permission data
7. **Configurable Trust Levels** - Applications control middleware access

---

## Performance Architecture

### Request Processing Flow

```
Request → Skip Path Check → JWT Extract → Validate → Multi-Tenant → RBAC → Continue
   │         (μs)              (1-2ms)    (1ms)       (<1ms)      (1ms)
   │
   └─── Skip Path Hit → Continue (bypass all processing)
```

### Caching Strategy

**Layer 1: Path Skipping**

- Pre-compiled regex patterns
- O(1) lookup for common public paths
- Bypasses all JWT processing

**Layer 2: JWT Validation**

- Compatible with external JWT caching solutions
- Algorithm verification cached per secret

**Layer 3: Permission Caching**

- User permission results cached with TTL
- Timestamp-based invalidation
- Configurable backends: Redis, Memory, Memcached

### Performance Targets

- **Skip Path Check:** < 100μs
- **JWT Validation:** < 2ms
- **Multi-Tenant Validation:** < 1ms
- **RBAC Permission Check:** < 1ms (cached)
- **Total Overhead:** < 5ms per request

---

## Configuration Architecture

### Hierarchical Configuration System

```ruby
RackJwtBastion::Middleware.new(app, {
  # Core JWT (Required)
  jwt_secret: ENV['JWT_SECRET'],
  jwt_algorithm: 'HS256',

  # Optional Features (Default: disabled)
  validate_subdomain: false,
  validate_company_slug: false,
  rbac_enabled: false,

  # Path Management
  skip_paths: ['/health', '/login'],
  company_slug_pattern: /^\/api\/v1\/([^\/]+)\//,

  # Multi-Tenant Configuration
  company_header_name: 'X-Company-Group-Id',
  payload_mapping: {
    user_id: :sub,
    company_group_id: :company_id,
    company_group_domain: :domain,
    company_slugs: :accessible_companies
  },

  # RBAC Cache Configuration
  cache_store: :redis,
  cache_options: { url: 'redis://localhost:6379' },
  cache_write_enabled: true,  # High trust mode

  # Alternative: Zero trust mode
  rbac_cache_store: :redis,
  rbac_cache_options: { url: 'redis://app:6379' },
  permission_cache_store: :memory,
  permission_cache_options: {},

  # Custom Validation
  custom_payload_validator: ->(payload, request) {
    payload['role'] == 'admin'
  },

  # Response Customization
  unauthorized_response: { error: 'Authentication required' },
  forbidden_response: { error: 'Access denied' },

  # Development
  debug_mode: Rails.env.development?
})
```

---

## Implementation Architecture

### Module Structure

```
lib/
├── rack_jwt_bastion.rb              # Main entry point
├── rack_jwt_bastion/
│   ├── middleware.rb                # Core middleware class
│   ├── configuration.rb             # Configuration management
│   ├── jwt_validator.rb             # JWT token validation
│   ├── multi_tenant_validator.rb    # Subdomain & company slug validation
│   ├── rbac_manager.rb              # Role-based access control
│   ├── cache_adapter.rb             # Cache abstraction layer
│   ├── request_context.rb           # Request environment management
│   ├── response_builder.rb          # HTTP response generation
│   └── version.rb                   # Gem version
```

### Class Relationships

```ruby
class Middleware
  def initialize(app, options = {})
    @config = Configuration.new(options)
    @jwt_validator = JwtValidator.new(@config)
    @multi_tenant_validator = MultiTenantValidator.new(@config)
    @rbac_manager = RbacManager.new(@config) if @config.rbac_enabled?
    @response_builder = ResponseBuilder.new(@config)
  end

  def call(env)
    # Main request processing pipeline
  end
end
```

---

## Deployment Scenarios

### Scenario 1: Basic JWT Authentication

```ruby
# Minimal configuration for simple JWT validation
use RackJwtBastion::Middleware, {
  jwt_secret: ENV['JWT_SECRET']
}
```

### Scenario 2: Multi-Tenant SaaS Application

```ruby
# Full multi-tenant support without RBAC
use RackJwtBastion::Middleware, {
  jwt_secret: ENV['JWT_SECRET'],
  validate_subdomain: true,
  validate_company_slug: true,
  company_header_name: 'X-Company-Group-Id'
}
```

### Scenario 3: Enterprise with Fine-Grained Permissions

```ruby
# Complete RBAC with shared cache
use RackJwtBastion::Middleware, {
  jwt_secret: ENV['JWT_SECRET'],
  validate_subdomain: true,
  validate_company_slug: true,
  rbac_enabled: true,
  cache_store: :redis,
  cache_write_enabled: true
}
```

### Scenario 4: Zero-Trust High-Security Environment

```ruby
# RBAC with isolated caches
use RackJwtBastion::Middleware, {
  jwt_secret: ENV['JWT_SECRET'],
  rbac_enabled: true,
  rbac_cache_store: :redis,
  rbac_cache_options: { url: 'redis://secure-app:6379' },
  permission_cache_store: :memory,
  cache_write_enabled: false  # No write access to app cache
}
```

---

## Testing Architecture

### Test Coverage Strategy

**Unit Tests:**

- JWT validation with various payloads and algorithms
- Multi-tenant validation edge cases
- RBAC permission logic
- Cache adapter functionality
- Configuration validation

**Integration Tests:**

- Full middleware stack processing
- Different Rack application types (Rails, Sinatra, Pure Rack)
- Cache store integrations (Redis, Memory, Memcached)
- Error scenarios and edge cases

**Security Tests:**

- Token tampering attempts
- Subdomain spoofing attacks
- Cross-tenant access attempts
- Cache poisoning scenarios
- Trust boundary violations

**Performance Tests:**

- Request processing latency
- Cache performance under load
- Memory usage profiling
- Concurrent request handling

### Test Coverage Target

- **Minimum:** 95% code coverage
- **Framework:** Minitest with shoulda-context and mocha
- **CI/CD:** GitHub Actions with multiple Ruby versions

---

## Migration and Adoption Strategy

### From Existing JWT Middleware

**Common Migration Patterns:**

```ruby
# From rack-jwt
# OLD
use Rack::JWT::Auth, {
  secret: ENV['JWT_SECRET'],
  exclude: ['/health']
}

# NEW
use RackJwtBastion::Middleware, {
  jwt_secret: ENV['JWT_SECRET'],
  skip_paths: ['/health']
}
```

### Incremental Feature Adoption

1. **Phase 1:** Replace existing JWT middleware with basic configuration
2. **Phase 2:** Enable multi-tenant features (subdomain + company slug)
3. **Phase 3:** Implement RBAC with shared cache
4. **Phase 4:** Optimize with zero-trust cache isolation if needed

---

## Monitoring and Observability

### Metrics Collection

**Performance Metrics:**

- Request processing latency (p50, p95, p99)
- Cache hit/miss ratios
- JWT validation success/failure rates
- Feature utilization (which validations are triggered)

**Security Metrics:**

- Authentication failure patterns
- Cross-tenant access attempts
- Permission denial frequencies
- Cache invalidation rates

**Integration Points:**

- Standard Rack middleware metrics
- Custom instrumentation hooks
- Support for APM tools (New Relic, Datadog)
- Structured logging with correlation IDs

---

## Future Roadmap

### Version 0.1.0 (MVP)

- Basic JWT validation
- Multi-tenant subdomain validation
- Company slug validation
- Basic configuration system

### Version 0.2.0 (RBAC)

- Role-based access control
- Flexible cache store support
- Trust boundary configuration

### Version 0.3.0 (Advanced Features)

- JWT rotation support
- Advanced caching strategies
- Performance optimizations
- Enhanced monitoring

### Version 1.0.0 (Production Ready)

- Complete test coverage
- Performance benchmarking
- Security audit
- Comprehensive documentation

---

## Risk Assessment

### Technical Risks

**High Impact:**

- **Cache Corruption:** RBAC data corruption could break authorization
  - _Mitigation:_ Isolated cache modes, data validation
- **Performance Degradation:** Poor caching could impact response times
  - _Mitigation:_ Performance testing, optimized cache keys
- **Security Vulnerabilities:** JWT validation bugs could compromise security
  - _Mitigation:_ Comprehensive security testing, regular audits

**Medium Impact:**

- **Configuration Complexity:** Users might misconfigure trust modes
  - _Mitigation:_ Clear documentation, validation checks
- **Cache Dependency:** External cache failures could break RBAC
  - _Mitigation:_ Graceful degradation, fallback strategies

### Adoption Risks

- **Learning Curve:** Complex configuration options
- **Migration Effort:** Switching from existing solutions
- **Performance Concerns:** Users worried about middleware overhead

---

## Success Metrics

### Technical Metrics

- **Performance:** < 5ms processing overhead
- **Reliability:** 99.9% uptime compatibility
- **Security:** Zero critical vulnerabilities in 6 months
- **Test Coverage:** > 95% code coverage

### Adoption Metrics

- **Community:** 1000+ gem downloads in first 6 months
- **Feedback:** Positive user feedback on flexibility and security
- **Integration:** Usage in at least 3 different types of applications

---

## Conclusion

Rack JWT Bastion addresses a clear gap in the Ruby ecosystem by providing integrated JWT authentication, multi-tenant support, and fine-grained RBAC in a single, configurable middleware. The security-first architecture respects trust boundaries while providing flexible deployment options for different organizational needs.

The modular design allows teams to adopt features incrementally, starting with basic JWT validation and adding multi-tenant and RBAC capabilities as requirements evolve. The dual caching architecture balances performance optimization with security isolation requirements.

This architecture provides a solid foundation for building secure, performant multi-tenant applications while maintaining the flexibility needed for diverse deployment scenarios.

---

## Related Documents

- [features.md](features.md) - Core feature specifications
- [cache_store_architecture.md](cache_store_architecture.md) - Detailed caching system design
- [JWT_Middleware_Gem_Battleplan.md](JWT_Middleware_Gem_Battleplan.md) - Project implementation plan

---

_Document Version: 1.0_
_Last Updated: 2025-08-10_
\*Author: Ken C. Demanawa
