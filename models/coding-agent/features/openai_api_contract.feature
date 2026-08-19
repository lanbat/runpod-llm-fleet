Feature: OpenAI-compatible API contract and thinking-mode override
  The vLLM worker's chat template was patched to force Qwen3's "thinking"
  mode off unconditionally, because leaked <think> reasoning in the content
  field was corrupting opencode's tool-calling loop (see agentic_stability
  feature). These scenarios guard against that regressing.

  Scenario: A plain request returns its answer in the content field
    When I send a chat completion request with the prompt "Reply with exactly: pong"
    Then the response message.content field equals "pong" (ignoring whitespace)
    And the response message.reasoning field is null
    And the completion token count is less than 10

  Scenario: An explicit request to re-enable thinking is ignored
    When I send a chat completion request with chat_template_kwargs.enable_thinking = true
    And the same prompt "Reply with exactly: pong"
    Then the response message.content field still equals "pong" (ignoring whitespace)
    And the completion token count is still less than 10
    And no "<think>" substring appears anywhere in the response

  Scenario: Tool-calling is enabled and returns structured tool_calls
    Given a request that includes a tool definition the model should call
    When the model decides to use the tool
    Then the response's tool_calls array is populated
    And the message.content field is not a raw "<tool_call>" text blob
