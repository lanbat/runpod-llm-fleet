Feature: Always-on endpoint availability
  Unlike coding-agent (scale-to-zero), this endpoint runs workersMin=1 so voice
  commands never hit a cold start.

  Scenario: Endpoint responds quickly on every request, not just the first
    Given the endpoint has workersMin=1 (always-on)
    When I send three sequential chat completion requests
    Then every response completes in under 5 seconds
    And no request is delayed by a cold start
