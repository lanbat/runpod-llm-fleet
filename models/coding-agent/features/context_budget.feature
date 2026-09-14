Feature: opencode's context budget fits the endpoint's MAX_MODEL_LEN
  opencode sends max_tokens = min(limit.output, 32000) on every request, and only
  compacts after a step has pushed the prompt past limit.context - max_tokens. The
  request that crosses that line can therefore overshoot by one step's tool output.
  With limit.context equal to MAX_MODEL_LEN (the 65536/65536 Qwen3-Coder-Next config),
  that request exceeded the endpoint's context window, came back empty, and opencode
  looped on empty steps until "SSE read timed out" (RomM session, 2026-09-13).

  Scenario: The largest request opencode can send is accepted
    Given limit.context and limit.output from opencode-config.jsonc
    When I send a prompt of (limit.context - max_tokens + 10000) tokens
    And max_tokens = min(limit.output, 32000)
    Then the endpoint returns non-empty content
