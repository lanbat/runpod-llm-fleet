Feature: OpenAI-compatible API contract for a thinking model
  Qwen3.8-27B thinks by default. vLLM's qwen3 reasoning parser must move that
  reasoning into message.reasoning so it never leaks into content (leaked <think>
  text previously corrupted opencode's tool-calling loop — see agentic_stability
  feature). The endpoint defaults reasoning_effort to "low" server-side via
  --default-chat-template-kwargs.

  Scenario: Thinking can be disabled per request
    When I send "Reply with exactly: pong" with chat_template_kwargs.enable_thinking = false
    Then the response message.content field equals "pong" (ignoring whitespace)
    And the response message.reasoning field is null
    And the completion token count is less than 10

  Scenario: Default requests think, but reasoning stays out of content
    When I send "Reply with exactly: pong" with no thinking overrides
    Then the response message.content field contains "pong"
    And the response message.reasoning field is non-empty
    And no "<think>" substring appears in message.content

  Scenario: Tool-calling is enabled and returns structured tool_calls
    Given a request that includes a get_weather tool definition
    When I ask for the current weather in Paris
    Then the response's tool_calls array calls get_weather with a city containing "Paris"
    And the message.content field is not a raw "<tool_call>" text blob
