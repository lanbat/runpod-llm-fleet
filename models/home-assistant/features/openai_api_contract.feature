Feature: OpenAI-compatible API contract and thinking-mode override
  Same class of fix as coding-agent: the chat template was patched to force
  Qwen3's "thinking" mode off unconditionally, pre-emptively (before ever hitting
  the bug in production, unlike coding-agent where it was discovered live).

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
