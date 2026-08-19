Feature: opencode <-> RunPod provider integration
  opencode is configured with a "runpod" provider in
  ~/.config/opencode/opencode.jsonc pointing at the endpoint's
  OpenAI-compatible route.

  Scenario: opencode recognizes the RunPod provider and model
    When I run `opencode models runpod`
    Then the output includes "runpod/qwen3-32b"

  Scenario: opencode completes a simple one-shot prompt
    When I run `opencode run --model runpod/qwen3-32b "Write a one-line python function that adds two numbers. Just the code, no explanation."`
    Then the process exits with code 0
    And the output contains a python lambda or def for addition

  Scenario: RUNPOD_API_KEY is available to opencode
    Given RUNPOD_API_KEY is exported in the shell profile (~/.zshrc)
    When opencode makes a request to the runpod provider
    Then the request does not fail with 401 Unauthorized
