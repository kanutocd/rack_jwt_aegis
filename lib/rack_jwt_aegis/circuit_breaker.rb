# frozen_string_literal: true

require 'ratomic'

module RackJwtAegis
  class CircuitBreaker
    STATE_FAILURE_COUNT = 'failure_count'
    STATE_OPENED_AT = 'opened_at'

    def initialize(failure_threshold:, cooldown_seconds:)
      @failure_threshold = failure_threshold.to_i
      @cooldown_seconds = cooldown_seconds.to_i
      @state = Ratomic::Map.new
      reset
    end

    def allow_request?
      return true unless open?
      return false unless cooldown_elapsed?

      reset
      true
    end

    def record_success
      reset
    end

    def record_failure
      failures = @state.increment(STATE_FAILURE_COUNT)
      @state[STATE_OPENED_AT] = Time.now.to_f if failures >= @failure_threshold
      failures
    end

    def open?
      !@state[STATE_OPENED_AT].nil?
    end

    private

    def reset
      @state[STATE_FAILURE_COUNT] = 0
      @state.delete(STATE_OPENED_AT)
    end

    def cooldown_elapsed?
      opened_at = @state[STATE_OPENED_AT]
      opened_at && (Time.now.to_f - opened_at) >= @cooldown_seconds
    end
  end
end
