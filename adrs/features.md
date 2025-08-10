# The incoming request Authentication/Verification based on the JWT payload

All the features below except for the "Basic JWT Verification" can be turn on or off.

## Basic JWT Verification

## Request URL Host's Subdomain Isolation/Verification/Validation (Level 1 Multi-Tenant)

Validates the top-level tenant in a 2-level hierarchy:
- Company-Group → Company
- Organization → Department  
- Company → Project

## Request URL Pathname Slug Segment Verification/Validation (Level 2 Multi-Tenant)

Validates the sub-level tenant within the top-level tenant hierarchy:
- Extracts company slug from URL path
- Validates user has access to specific company within their company-group
- Supports various tenant structures (divisions, departments, projects, etc.)

## Role Based Access Control (RBAC) based on request url pathname and request http method/verb (POST, PUT, DELETE, PATCH, GET)

### Rack based application responsibility:

- the RBAC collection must be stored in a cache or shared memory that the Rack has permission to read
- the Rack based application must store the RBAC collection to this cache-store
- the Rack based application's responsibility is to maintain this RBAC collection
- this cache-store must have a key-value entry of: {last-update}:{unix-like-timestamp}. This entry will be checked against the cached users validated permissions

### The middleware will cache (with expiration) everytime the request got successfully validated.

- this cache pattern can be: {user-identity}:{url-host}:{url-pathname}:{http-method}:{expires-at}
