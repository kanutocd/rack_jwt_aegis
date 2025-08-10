# frozen_string_literal: true

require 'json'

module RackJwtAegis
  class ResponseBuilder
    def initialize(config)
      @config = config
    end

    def unauthorized_response(message = nil)
      error_response(
        message || @config.unauthorized_response[:error] || 'Authentication required',
        401,
      )
    end

    def forbidden_response(message = nil)
      error_response(
        message || @config.forbidden_response[:error] || 'Access denied',
        403,
      )
    end

    def error_response(message, status_code)
      response_body = build_error_body(message, status_code)

      [
        status_code,
        {
          'Content-Type' => 'application/json',
          'Content-Length' => response_body.bytesize.to_s,
          'Cache-Control' => 'no-cache, no-store, must-revalidate',
          'Pragma' => 'no-cache',
          'Expires' => '0',
        },
        [response_body],
      ]
    end

    private

    def build_error_body(message, status_code)
      error_data = {
        error: message,
        status: status_code,
        timestamp: Time.now.iso8601,
      }

      # Add additional context in debug mode
      if @config.debug_mode?
        error_data[:middleware] = 'rack_jwt_aegis'
        error_data[:version] = RackJwtAegis::VERSION
      end

      JSON.generate(error_data)
    end
  end
end
