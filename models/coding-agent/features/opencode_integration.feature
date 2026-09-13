Feature: opencode <-> RunPod provider integration
  opencode is configured with a "runpod" provider in
  ~/.config/opencode/opencode.jsonc pointing at the endpoint's
  OpenAI-compatible route.

  Scenario: opencode recognizes the RunPod provider and model
    When I run `opencode models runpod`
    Then the output includes "runpod/qwen3-coder-next"

  Scenario: opencode completes a simple one-shot prompt
    When I run `opencode run --model runpod/qwen3-coder-next "Write a one-line python function that adds two numbers. Just the code, no explanation."`
    Then the process exits with code 0
    And the output contains a python lambda or def for addition

  Scenario: RunPod API key is available to opencode
    Given ~/.config/envman/RUNPOD.key exists (synced from RUNPOD_API_KEY via sync-runpod-key.sh)
    And ~/.config/opencode/opencode.jsonc uses {file:~/.config/envman/RUNPOD.key}
    When opencode makes a request to the runpod provider
    Then the request does not fail with 401 Unauthorized
