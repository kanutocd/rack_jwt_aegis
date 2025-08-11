# frozen_string_literal: true

require_relative 'rack_jwt_aegis/version'
require_relative 'rack_jwt_aegis/configuration'
require_relative 'rack_jwt_aegis/middleware'
require_relative 'rack_jwt_aegis/jwt_validator'
require_relative 'rack_jwt_aegis/multi_tenant_validator'
require_relative 'rack_jwt_aegis/rbac_manager'
require_relative 'rack_jwt_aegis/cache_adapter'
require_relative 'rack_jwt_aegis/request_context'
require_relative 'rack_jwt_aegis/response_builder'

# @author Ken Camajalan Demanawa
# @since 0.1.0
#
# RackJwtAegis is a comprehensive JWT authentication and authorization middleware for Rack applications.
# It provides multi-tenant support, RBAC (Role-Based Access Control), and caching capabilities.
#
# Features:
# - JWT token validation with configurable algorithms
# - Multi-tenant validation (subdomain and pathname slug based)
# - RBAC with flexible permission caching
# - Multiple cache adapter support (Memory, Redis, Memcached, SolidCache)
# - Request context management
# - Configurable skip paths and custom validators
#
# @example Basic usage
#   use RackJwtAegis::Middleware, jwt_secret: ENV['JWT_SECRET']
#
# @example Multi-tenant with RBAC
#   use RackJwtAegis::Middleware, {
#     jwt_secret: ENV['JWT_SECRET'],
#     validate_subdomain: true,
#     validate_pathname_slug: true,
#     rbac_enabled: true,
#     cache_store: :redis,
#     cache_write_enabled: true
#   }
module RackJwtAegis
  # Base error class for all RackJwtAegis exceptions
  class Error < StandardError; end

  # Raised when configuration is invalid or missing required parameters
  class ConfigurationError < Error; end

  # Raised when JWT authentication fails
  class AuthenticationError < Error; end

  # Raised when authorization/permission checks fail
  class AuthorizationError < Error; end

  # Raised when cache operations fail
  class CacheError < Error; end
end
