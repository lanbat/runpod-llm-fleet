Feature: RunPod serverless endpoint availability
  The Qwen3-32B endpoint should scale down when idle to save cost, scale up
  on demand, and stay warm during an active session.

  Scenario: Endpoint responds when a worker is already warm
    Given a worker for the endpoint is in the "ready" or "idle" state
    When I send a simple chat completion request
    Then I receive a completed response within 15 seconds
    And the response message content is non-empty

  Scenario: Endpoint scales up from zero workers
    Given no workers are currently running for the endpoint
    When I send a chat completion request
    Then a worker initializes and begins serving
    And the request completes within 5 minutes

  Scenario: Worker stays warm between quick successive requests
    Given a request completed less than 10 minutes ago
    When I send another request immediately after
    Then no new cold start occurs
    And the response returns in under 15 seconds
