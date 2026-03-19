defmodule JidoSessions.Parsers.GeminiTest do
  use ExUnit.Case, async: true

  alias JidoSessions.Parsers.Gemini

  test "parses user + gemini with thoughts and content" do
    events = [
      %{type: "user", data: %{"content" => "Explain this"}, timestamp: nil},
      %{
        type: "gemini",
        data: %{
          "content" => "Here's the explanation.",
          "thoughts" => [
            %{"subject" => "Analysis", "description" => "checking the code"}
          ],
          "tokens" => %{"input" => 500, "output" => 200},
          "model" => "gemini-2.5-pro"
        },
        timestamp: nil
      }
    ]

    [turn] = Gemini.parse_turns(events)
    assert turn.user_content == "Explain this"
    assert turn.reasoning =~ "Analysis"
    assert turn.assistant_content == "Here's the explanation."
    assert turn.usage.model == "gemini-2.5-pro"
    assert turn.usage.input_tokens == 500
  end

  test "parses toolCalls with output" do
    events = [
      %{type: "user", data: %{"content" => "List files"}, timestamp: nil},
      %{
        type: "gemini",
        data: %{
          "content" => "Found files.",
          "toolCalls" => [
            %{
              "name" => "run_shell_command",
              "id" => "gc1",
              "args" => %{"command" => "ls"},
              "output" => "README.md\nlib/"
            }
          ]
        },
        timestamp: nil
      }
    ]

    [turn] = Gemini.parse_turns(events)
    assert length(turn.tool_calls) == 1
    [tc] = turn.tool_calls
    assert tc.tool == :shell
  end
end
