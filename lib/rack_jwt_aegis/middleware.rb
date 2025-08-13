# frozen_string_literal: true

module RackJwtAegis
  # Main Rack middleware for JWT authentication and authorization
  #
  # This middleware handles the complete JWT authentication flow including:
  # - JWT token extraction and validation
  # - Multi-tenant validation (subdomain/pathname slug)
  # - RBAC permission checking
  # - Custom payload validation
  # - Request context setting
  #
  # @author Ken Camajalan Demanawa
  # @since 0.1.0
  #
  # @example Basic usage
  #   use RackJwtAegis::Middleware, jwt_secret: ENV['JWT_SECRET']
  #
  # @example Advanced usage
  #   use RackJwtAegis::Middleware, {
  #     jwt_secret: ENV['JWT_SECRET'],
  #     validate_subdomain: true,
  #     rbac_enabled: true,
  #     cache_store: :redis,
  #     skip_paths: ['/health', '/api/public/*']
  #   }
  class Middleware
    # Initialize the middleware
    #
    # @param app [#call] the Rack application
    # @param options [Hash] configuration options (see Configuration#initialize)
    def initialize(app, options = {})
      @app = app
      @config = Configuration.new(options)

      # Initialize components
      @jwt_validator = JwtValidator.new(@config)
      @multi_tenant_validator = MultiTenantValidator.new(@config) if multi_tenant_enabled?
      @rbac_manager = RbacManager.new(@config) if @config.rbac_enabled?
      @response_builder = ResponseBuilder.new(@config)
      @request_context = RequestContext.new(@config)

      debug_log("Middleware initialized with features: #{enabled_features}")
    end

    # Process the Rack request
    #
    # @param env [Hash] the Rack environment
    # @return [Array] Rack response array [status, headers, body]
    # @raise [AuthenticationError] if JWT authentication fails
    # @raise [AuthorizationError] if authorization checks fail
    def call(env)
      request = Rack::Request.new(env)

      debug_log("Processing request: #{request.request_method} #{request.path}")

      # Step 1: Check if path should be skipped
      if @config.skip_path?(request.path)
        debug_log("Skipping authentication for path: #{request.path}")
        return @app.call(env)
      end

      begin
        # Step 2: Extract and validate JWT token
        token = extract_jwt_token(request)
        payload = @jwt_validator.validate(token)

        debug_log("JWT validation successful for user: #{payload[@config.payload_key(:user_id).to_s]}")

        # Step 3: Multi-tenant validation (if enabled)
        if multi_tenant_enabled?
          @multi_tenant_validator.validate(request, payload)
          debug_log('Multi-tenant validation successful')
        end

        # Step 4: RBAC permission check (if enabled)
        if @config.rbac_enabled?
          # Extract and store user roles in request environment for RBAC manager
          user_roles = extract_user_roles(payload)
          request.env['rack_jwt_aegis.user_roles'] = user_roles

          @rbac_manager.authorize(request, payload)
          debug_log('RBAC authorization successful')
        end

        # Step 5: Custom payload validation (if configured)
        if @config.custom_payload_validator
          unless @config.custom_payload_validator.call(payload, request)
            debug_log('Custom payload validation failed')
            raise AuthorizationError, 'Custom validation failed'
          end
          debug_log('Custom payload validation successful')
        end

        # Step 6: Set request context for application
        @request_context.set_context(env, payload)
        debug_log('Request context set successfully')

        # Continue to application
        @app.call(env)
      rescue AuthenticationError => e
        debug_log("Authentication failed: #{e.message}")
        @response_builder.unauthorized_response(e.message)
      rescue AuthorizationError => e
        debug_log("Authorization failed: #{e.message}")
        @response_builder.forbidden_response(e.message)
      rescue StandardError => e
        debug_log("Unexpected error: #{e.message}")
        if @config.debug_mode?
          @response_builder.error_response("Internal error: #{e.message}", 500)
        else
          @response_builder.error_response('Internal server error', 500)
        end
      end
    end

    private

    # Extract JWT token from the Authorization header
    #
    # @param request [Rack::Request] the Rack request object
    # @return [String] the extracted JWT token
    # @raise [AuthenticationError] if authorization header is missing or invalid
    def extract_jwt_token(request)
      auth_header = request.get_header('HTTP_AUTHORIZATION')

      raise AuthenticationError, 'Authorization header missing' if auth_header.nil? || auth_header.empty?

      # Extract Bearer token
      match = auth_header.match(/\ABearer\s+(.+)\z/)
      raise AuthenticationError, 'Invalid authorization header format' if match.nil?

      token = match[1]
      raise AuthenticationError, 'JWT token missing' if token.nil? || token.empty?

      token
    end

    # Check if multi-tenant validation is enabled
    #
    # @return [Boolean] true if subdomain or pathname slug validation is enabled
    def multi_tenant_enabled?
      @config.validate_subdomain? || @config.validate_pathname_slug?
    end

    # Generate a string describing enabled features for logging
    #
    # @return [String] comma-separated list of enabled features
    def enabled_features
      features = ['JWT']
      features << 'Subdomain' if @config.validate_subdomain?
      features << 'CompanySlug' if @config.validate_pathname_slug?
      features << 'RBAC' if @config.rbac_enabled?
      features.join(', ')
    end

    # Extract user roles from JWT payload for RBAC authorization
    #
    # @param payload [Hash] the JWT payload
    # @return [Array] array of user role IDs
    def extract_user_roles(payload)
      # Use configured payload mapping for role_ids, with fallback to common field names
      role_key = @config.payload_key(:role_ids).to_s
      roles = payload[role_key]

      # If mapped key doesn't exist, try common fallback field names
      roles = payload['roles'] || payload['role'] || payload['user_roles'] || payload['role_ids'] if roles.nil?

      case roles
      when Array
        roles.map(&:to_s) # Ensure all roles are strings for consistent lookup
      when String, Integer
        [roles.to_s] # Single role as array
      else
        debug_log("Warning: No valid roles found in JWT payload. Looking for '#{role_key}' field. \
                   Available fields: #{payload.keys}".squeeze)
        []
      end
    end

    # Log debug message if debug mode is enabled
    #
    # @param message [String] the message to log
    def debug_log(message)
      return unless @config.debug_mode?

      timestamp = Time.now.strftime('%Y-%m-%d %H:%M:%S.%L')
      puts "[#{timestamp}] RackJwtAegis: #{message}"
    end
  end
end
