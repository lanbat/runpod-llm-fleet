Feature: Repo awareness via tool calling
  opencode gives the model Read/Glob/Grep tools so answers should be
  grounded in actual repo contents, not generic/hallucinated text.

  Scenario: opencode reads a specific file when asked about it
    Given a test directory containing a file with a unique marker string
    When I ask opencode to quote the marker from that file
    Then opencode invokes the Read tool on that exact file path
    And the final answer contains the exact marker string

  Scenario: opencode grounds answers in a large, real repository
    Given a repository with thousands of files and a specific config file
      containing known values (e.g. bucket name, region, role ARN)
    When I ask a question about that specific config file
    Then opencode globs and/or reads the relevant file
    And the final answer cites the specific known values verbatim
    And the answer is not a generic/templated explanation of the file type
