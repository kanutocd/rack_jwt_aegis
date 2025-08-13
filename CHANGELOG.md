# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.1] - 2025-08-13

### 🔧 Fixed

#### Code Quality & Maintenance

- **DRY Refactoring**: Eliminated duplicate `debug_log` method implementations by creating a shared `DebugLogger` module
  - Created `lib/rack_jwt_aegis/debug_logger.rb` with consistent debug logging functionality
  - Updated `Middleware` and `RbacManager` classes to include the shared module
  - Improved code maintainability by centralizing debug logging logic
  - Maintains all existing functionality and logging behavior
- **RBAC Cache Validation**: Enhanced wildcard permission validation in `validate_rbac_cache_format` to support `admin/*` patterns
- **JWT Payload Resolution**: Fixed JWT payload key resolution to handle string keys consistently across components
- **Test Coverage**: Maintained high test coverage (98.17% line coverage) after refactoring

#### Developer Experience

- **Consistent Logging**: Unified debug log format across all components with automatic timestamp formatting
- **Component Identification**: Automatic component name inference for better log traceability  
- **Configurable Log Levels**: Support for info, warn, and error log levels with appropriate output streams

### 🏗️ Technical Details

#### Architecture Improvements

- **Shared Module Pattern**: Introduced consistent module inclusion pattern for cross-cutting concerns
- **Code Organization**: Better separation of concerns with dedicated debug logging module
- **Maintainability**: Reduced code duplication from ~40 lines to a single shared implementation

#### Testing & Quality

- **Test Suite**: All 340 tests pass with 975 assertions
- **Coverage Maintained**: 98.17% line coverage, 92.83% branch coverage  
- **RBAC Integration**: Verified all role-based authorization tests pass after refactoring
- **Zero Regression**: No functional changes, only structural improvements

---

## [1.0.0] - 2025-08-13

### 🎉 Initial Release

This is the first stable release of Rack JWT Aegis, a JWT authentication middleware for hierarchical multi-tenant Rack applications.

### ✨ Added

#### Core Authentication Features

- **JWT Token Validation** with configurable algorithms (HS256, HS384, HS512, RS256, RS384, RS512, ES256, ES384, ES512)
- **Multi-Tenant Support** with 2-level hierarchy (Company-Group → Company, Organization → Department, etc.)
- **Subdomain-based Tenant Isolation** for top-level tenants
- **URL Pathname Slug Access Control** for sub-level tenants with regex pattern support
- **Configurable Path Exclusions** for public endpoints with flexible pattern matching
- **Custom Payload Validation** with user-defined validation logic
- **Request Context Access** with convenient helper methods for accessing JWT payload data

#### RBAC (Role-Based Access Control)

- **Fine-grained Permission System** with resource:method format (e.g., `users:get`, `reports:post`)
- **Wildcard Method Support** (e.g., `admin/*` for all methods)
- **Regex Pattern Matching** for dynamic resource paths (e.g., `%r{users/\d+}:put`)
- **Multi-tier Caching** for performance optimization
- **Cache Write Control** with zero-trust mode support
- **Permission Cache TTL** with configurable expiration
- **Debug Mode** with comprehensive logging

#### Caching System

- **Multiple Cache Adapters**:
  - Memory adapter (built-in, thread-safe)
  - Redis adapter with connection pooling
  - Memcached adapter with Dalli integration
  - SolidCache adapter for Rails 8+ applications
- **Intelligent Cache Invalidation** based on RBAC updates
- **Performance Optimization** with counter caches and eager loading
- **Error Handling** with graceful fallback and retry logic

#### CLI Tool

- **JWT Secret Generation** with multiple formats (plain, base64, environment variable)
- **Batch Secret Generation** for multiple environments
- **Secure Random Generation** using cryptographically secure methods

#### Configuration & Validation

- **Flexible Configuration** with sensible defaults
- **Multi-tenant Validation** with header-based and URL-based strategies
- **Custom Validation Hooks** for business-specific requirements
- **Debug Mode** for development and troubleshooting

#### Developer Experience

- **Comprehensive Documentation** with YARD-generated API docs
- **GitHub Pages Integration** with automatic deployment
- **High Test Coverage** (97.8% line coverage, 86.6% branch coverage)
- **RuboCop Integration** with style enforcement
- **Code Examples** for common use cases

### 🏗️ Technical Implementation

#### Architecture

- **Modular Design** with clear separation of concerns
- **Rack Middleware** integration for framework independence
- **Thread-safe Operations** for concurrent request handling
- **Memory Efficient** with optimized data structures
- **Error Boundary** with proper exception handling

#### Testing & Quality

- **Comprehensive Test Suite** with Minitest framework
- **Mock Integration** with Mocha for reliable testing
- **Cache Adapter Testing** with actual Redis and Dalli gems
- **Edge Case Coverage** for error handling and validation paths
- **Performance Testing** for cache operations and memory usage

#### Documentation & Workflows

- **GitHub Actions CI/CD** with multi-Ruby version testing
- **Automated Documentation Deployment** to GitHub Pages
- **Workflow Dispatch** for manual deployments
- **Coverage Reporting** with SimpleCov integration
- **Code Quality Checks** with RuboCop and documentation coverage

### 🔧 Configuration Examples

#### Basic JWT Authentication

```ruby
use RackJwtAegis::Middleware, {
  jwt_secret: ENV['JWT_SECRET'],
  jwt_algorithm: 'HS256'
}
```

#### Multi-tenant with RBAC

```ruby
use RackJwtAegis::Middleware, {
  jwt_secret: ENV['JWT_SECRET'],
  multi_tenant_enabled: true,
  subdomain_validation_enabled: true,
  rbac_enabled: true,
  rbac_cache_store: :redis,
  debug_mode: Rails.env.development?
}
```

#### Enterprise Configuration

```ruby
use RackJwtAegis::Middleware, {
  jwt_secret: ENV['JWT_SECRET'],
  jwt_algorithm: 'RS256',
  multi_tenant_enabled: true,
  subdomain_validation_enabled: true,
  pathname_slug_pattern: /^\/api\/v1\/([^\/]+)\//,
  rbac_enabled: true,
  rbac_cache_store: :redis,
  permission_cache_store: :memory,
  user_permissions_ttl: 300,
  cache_write_enabled: true,
  skip_paths: [/^\/health/, /^\/metrics/, /^\/api\/public/],
  custom_payload_validation: ->(payload) { payload['active'] == true },
  debug_mode: false
}
```

### 📚 Documentation

- **Online Documentation**: Auto-deployed to GitHub Pages
- **API Reference**: Complete YARD documentation for all classes and methods
- **Usage Examples**: Comprehensive examples for all features
- **Architecture Decisions**: ADRs documenting design choices
- **Integration Guides**: Framework-specific integration examples

### 🧪 Testing Coverage

- **Line Coverage**: 97.8% (668/683 lines)
- **Branch Coverage**: 86.6% (259/299 branches)
- **Test Files**: 15 comprehensive test suites
- **Test Cases**: 323+ individual test cases
- **Cache Integration**: Tests with actual Redis and Dalli gems

### 🔗 Dependencies

#### Core Dependencies

- `rack` (~> 3.0)
- `jwt` (~> 2.8)

#### Development Dependencies

- `redis` (~> 5.0) - For Redis cache adapter testing
- `dalli` (~> 3.0) - For Memcached cache adapter testing
- `minitest` (~> 5.25) - Test framework
- `mocha` (~> 2.7) - Mocking library
- `simplecov` (~> 0.22.0) - Coverage reporting
- `yard` (~> 0.9.37) - Documentation generation

### 🏆 Performance Characteristics

- **Memory Efficient**: Optimized data structures with cleanup routines
- **High Throughput**: Thread-safe operations with minimal locking
- **Low Latency**: Multi-tier caching with intelligent invalidation
- **Scalable**: Distributed caching support with Redis/Memcached

### 🛡️ Security Features

- **Secure Defaults**: Conservative configuration out of the box
- **Input Validation**: Comprehensive validation of all inputs
- **Error Handling**: Secure error messages without information leakage
- **Cache Security**: Proper serialization and data isolation
- **Debug Safety**: No sensitive data in debug output

### 🌟 Production Ready

This 1.0.0 release represents a production-ready JWT authentication middleware with:

- ✅ **Battle-tested** architecture with comprehensive edge case handling
- ✅ **High test coverage** ensuring reliability and stability
- ✅ **Flexible configuration** supporting diverse deployment scenarios
- ✅ **Performance optimized** with intelligent caching strategies
- ✅ **Comprehensive documentation** for easy adoption and maintenance
- ✅ **Active maintenance** with automated CI/CD and quality checks

---

**Migration Notes**: This is the initial release. No migration is required.

**Breaking Changes**: None (initial release).

**Deprecations**: None (initial release).

[1.0.1]: https://github.com/kanutocd/rack_jwt_aegis/releases/tag/v1.0.1
[1.0.0]: https://github.com/kanutocd/rack_jwt_aegis/releases/tag/v1.0.0
