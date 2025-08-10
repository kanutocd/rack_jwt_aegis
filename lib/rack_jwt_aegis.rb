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

module RackJwtAegis
  class Error < StandardError; end
  class ConfigurationError < Error; end
  class AuthenticationError < Error; end
  class AuthorizationError < Error; end
  class CacheError < Error; end
end
