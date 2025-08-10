# ADR: Flexible Cache Store Architecture for RBAC and Permission Caching

**Status:** Proposed  
**Date:** 2025-08-10  
**Context:** JWT authentication middleware with Role-Based Access Control (RBAC) feature

---

## Context

The rack_jwt_bastion middleware implements optional RBAC functionality that requires caching user permissions for performance. The design must balance performance, security, and flexibility while respecting the trust boundaries between middleware and host applications.

## Problem

When RBAC is enabled, the middleware needs:
1. Fast access to user permissions for request authorization
2. Access to master RBAC collection maintained by the application
3. Ability to cache validated permissions to avoid repeated lookups
4. Support for different cache store backends (Redis, Memory, Memcached, Solid Cache)

**Security Constraint:** Applications may legitimately not trust middleware with write access to their security-critical RBAC data.

## Decision

Implement a **flexible two-layer caching architecture** with configurable trust levels between application and middleware.

### Architecture Components

#### Layer 1: Application RBAC Store
**Purpose:** Master source of truth for permissions data  
**Responsibility:** Host application  
**Access Pattern:** Middleware reads, application writes  

**Required Entries:**
- RBAC collection data structure
- `{last-update}:{unix-timestamp}` for cache invalidation

#### Layer 2: Middleware Permission Cache  
**Purpose:** Performance optimization for validated permissions  
**Responsibility:** Middleware  
**Cache Pattern:** `{user-identity}:{url-host}:{url-pathname}:{http-method}:{expires-at}`

### Configuration Modes

#### Mode 1: Shared Cache Store (High Trust)
```ruby
RackJwtBastion::Middleware.new(app, {
  # Shared cache configuration
  cache_store: :redis,
  cache_options: { url: 'redis://localhost:6379' },
  cache_write_enabled: true,  # Middleware can write to shared store
  
  # RBAC feature enabled
  rbac_enabled: true
})
```

**Trust Model:** Application explicitly trusts middleware  
**Storage:** Single cache store shared by both application and middleware  
**Performance:** Optimal - everything in one cache  

#### Mode 2: Isolated Cache Stores (Zero Trust)  
```ruby
RackJwtBastion::Middleware.new(app, {
  # Application's RBAC cache (read-only for middleware)
  rbac_cache_store: :redis,
  rbac_cache_options: { url: 'redis://app:6379' },
  
  # Middleware's isolated permission cache
  permission_cache_store: :memory,
  permission_cache_options: {},
  
  cache_write_enabled: false,  # No write access to app cache
  rbac_enabled: true
})
```

**Trust Model:** Zero trust - middleware is treated as untrusted third-party  
**Storage:** Separate cache stores with clear access boundaries  
**Security:** Maximum isolation of critical RBAC data  

### Cache Flow Algorithm

1. **Fast Path Check:** Query middleware permission cache for exact match
2. **Cache Hit:** Return cached result if not expired and timestamp valid
3. **Cache Miss/Expired:** Query application RBAC store for permission data
4. **Timestamp Validation:** Compare cached permission timestamp vs application's `{last-update}`
5. **Cache Update:** Store validated result with expiration (if write access allowed)

### Cache Invalidation Strategy

**Timestamp-Based Invalidation:**
- Application updates `{last-update}:{unix-timestamp}` when RBAC data changes
- Middleware compares cached permission timestamp against current `{last-update}`
- Stale cached permissions are automatically invalidated

## Consequences

### Positive
- **Security-First:** Respects application trust boundaries and security concerns
- **Performance:** Two-layer caching provides sub-millisecond permission lookups
- **Flexibility:** Supports multiple cache backends and deployment scenarios
- **Principle of Least Privilege:** Middleware only gets minimum required access
- **Data Integrity:** Master RBAC data protected from middleware corruption

### Negative  
- **Configuration Complexity:** Two modes require careful configuration
- **Resource Usage:** Zero-trust mode uses additional cache store resources
- **Implementation Complexity:** Must support multiple cache adapters and access patterns

### Risks
- **Misconfiguration:** Incorrect cache store settings could break RBAC functionality
- **Performance Degradation:** Zero-trust mode has slightly higher latency due to separate stores
- **Cache Synchronization:** Timestamp-based invalidation requires careful implementation

## Implementation Requirements

### Cache Adapter Interface
```ruby
# Abstract cache adapter supporting multiple backends
class CacheAdapter
  def read(key)
  def write(key, value, expires_in: nil)  # Only if write_enabled
  def delete(key)  # Only if write_enabled
end
```

### Configuration Validation
- Validate cache store configurations at middleware initialization
- Ensure read access to application RBAC cache
- Verify write permissions match configuration settings

### Monitoring and Observability
- Cache hit/miss ratios for performance tuning
- Permission validation latency metrics
- Cache invalidation frequency tracking

---

## Related Documents
- [features.md](features.md) - Core middleware features including RBAC
- [JWT_Middleware_Gem_Battleplan.md](JWT_Middleware_Gem_Battleplan.md) - Overall project architecture

## Notes
This architecture enables applications to maintain full control over their security-critical RBAC data while allowing the middleware to provide optimal performance through configurable caching strategies.