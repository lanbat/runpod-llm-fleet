Feature: Home Assistant style tool calling
  Home Assistant exposes entities as tool/function definitions (e.g. HassTurnOn,
  HassTurnOff, HassSetTemperature). The model must reliably call the right
  function with the right arguments, in the standard OpenAI structured
  tool_calls format (not raw text).

  Scenario: A device-control request produces a correct structured tool call
    Given a tool definition named "HassTurnOn" with "name" and "area" parameters
    When I ask "Turn on the kitchen lights"
    Then the response's tool_calls array is populated
    And the called function is "HassTurnOn"
    And the arguments include a name referencing "kitchen" and/or "lights"
    And the response message.content field is not a raw tool-call text blob
