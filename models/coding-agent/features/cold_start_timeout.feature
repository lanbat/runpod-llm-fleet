Feature: opencode's streaming timeouts outlast a scale-to-zero cold start
  The endpoint runs workersMin=0, so the first request after idleTimeout wakes a worker
  that must download the 31 GB checkpoint, profile the KV cache and capture CUDA graphs
  (~4.5 min measured; docs quote 1-5+ min). RunPod's sync OpenAI route sends no SSE bytes
  at all while that happens, so the whole cold start counts against opencode's per-chunk
  timeout. With chunkTimeout=180000 (3 min) every cold start aborted at exactly 180s with
  "ProviderResponseStreamError: SSE read timed out"; each abort left its job running on the
  single allowed worker (workersMax=1, executionTimeoutMs=1800000), so opencode's retries
  stacked up behind orphaned jobs and the session never recovered (2026-09-20 session
  ses_f5ad6a9baffeLfr9tvD3epn2tH: six 3-minute aborts over 20 minutes).

  Scenario: chunkTimeout covers the worst-case cold start plus a full-context prefill
    Given timeout and chunkTimeout from opencode-config.jsonc
    Then chunkTimeout is at least the cold-start ceiling plus a prefill margin
    And timeout is greater than chunkTimeout

  Scenario: a warm worker still answers well inside the timeouts
    Given a warm endpoint
    When I stream a short completion
    Then the first SSE chunk arrives in far less than chunkTimeout
