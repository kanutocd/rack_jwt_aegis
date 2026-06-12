# frozen_string_literal: true

require 'test_helper'

class CircuitBreakerTest < Minitest::Test
  def test_opens_after_failure_threshold
    breaker = RackJwtAegis::CircuitBreaker.new(failure_threshold: 2, cooldown_seconds: 60)

    assert_predicate breaker, :allow_request?
    refute_predicate breaker, :open?

    breaker.record_failure

    assert_predicate breaker, :allow_request?
    refute_predicate breaker, :open?

    breaker.record_failure

    assert_predicate breaker, :open?
    refute_predicate breaker, :allow_request?
  end

  def test_allows_request_after_cooldown
    breaker = RackJwtAegis::CircuitBreaker.new(failure_threshold: 1, cooldown_seconds: 0)

    breaker.record_failure

    assert_predicate breaker, :open?
    assert_predicate breaker, :allow_request?
    refute_predicate breaker, :open?
  end
end
