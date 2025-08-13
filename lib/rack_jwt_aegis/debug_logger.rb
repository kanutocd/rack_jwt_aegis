# frozen_string_literal: true

module RackJwtAegis
  # Shared debug logging functionality
  #
  # Provides consistent debug logging across all RackJwtAegis components
  # with configurable log levels and automatic timestamp formatting.
  #
  # @author Ken Camajalan Demanawa
  # @since 1.0.0
  module DebugLogger
    # Log debug message if debug mode is enabled
    #
    # @param message [String] the message to log
    # @param level [Symbol] the log level (:info, :warn, :error) (default: :info)
    # @param component [String] the component name for log prefixing (optional)
    def debug_log(message, level = :info, component = nil)
      return unless @config.debug_mode?

      timestamp = Time.now.strftime('%Y-%m-%d %H:%M:%S.%L')

      # Determine component name for log prefix
      component_name = component || infer_component_name

      formatted_message = "[#{timestamp}] #{component_name}: #{message}"

      case level
      when :error, :warn
        warn formatted_message
      else
        puts formatted_message
      end
    end

    private

    # Infer component name from class name
    #
    # @return [String] the inferred component name
    def infer_component_name
      case self.class.name
      when /Middleware/
        'RackJwtAegis'
      when /RbacManager/
        'RbacManager'
      else
        self.class.name.split('::').last || 'RackJwtAegis'
      end
    end
  end
end
