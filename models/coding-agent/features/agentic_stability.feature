Feature: Agentic loop stability
  Regression guard for the bug where leaked <think> reasoning caused the
  model to restart its train of thought every turn, producing an infinite
  ping-pong of the same tool calls (see: EC2-provisioning session that
  alternated between the same two files ~15 times).

  Scenario: A multi-step task does not repeat the same tool call indefinitely
    Given a task that plausibly requires reading two or more related files
    When opencode executes the task to completion
    Then no single (tool name, tool input) pair is invoked more than 3 times
    And the session reaches a final text answer within 10 minutes

  Scenario: Assistant-visible text never contains raw <think> tags
    Given the session from the scenario above
    When I inspect every "text" part recorded for that session
    Then no part's text contains the literal substring "<think>"

  Scenario: A tool call that errors is not retried identically forever
    Given a task that causes one tool call to fail (e.g. file not found)
    When opencode continues the task
    Then the identical failing (tool, input) pair is not repeated more than 2 times
