defmodule JidoSessions.Parsers.ClaudeTest do
  use ExUnit.Case, async: true

  alias JidoSessions.Parsers.Claude

  test "parses user text + assistant text + thinking" do
    events = [
      %{
        type: "user",
        data: %{"message" => %{"content" => "Fix auth"}},
        timestamp: nil
      },
      %{
        type: "assistant",
        data: %{
          "message" => %{
            "content" => [
              %{"type" => "thinking", "thinking" => "I need to check verify_token"},
              %{"type" => "text", "text" => "Here's the fix."}
            ]
          }
        },
        timestamp: nil
      }
    ]

    [turn] = Claude.parse_turns(events)
    assert turn.user_content == "Fix auth"
    assert turn.reasoning =~ "verify_token"
    assert turn.assistant_content == "Here's the fix."
  end

  test "parses tool_use and tool_result" do
    events = [
      %{
        type: "user",
        data: %{"message" => %{"content" => "Check files"}},
        timestamp: nil
      },
      %{
        type: "assistant",
        data: %{
          "message" => %{
            "content" => [
              %{
                "type" => "tool_use",
                "id" => "toolu_1",
                "name" => "Bash",
                "input" => %{"command" => "ls"}
              }
            ]
          }
        },
        timestamp: nil
      },
      %{
        type: "user",
        data: %{
          "message" => %{
            "content" => [
              %{
                "type" => "tool_result",
                "tool_use_id" => "toolu_1",
                "content" => "README.md\nlib/",
                "is_error" => false
              }
            ]
          }
        },
        timestamp: nil
      }
    ]

    [turn] = Claude.parse_turns(events)
    assert length(turn.tool_calls) == 1
    [tc] = turn.tool_calls
    assert tc.tool == :shell
    assert tc.id == "toolu_1"
    assert tc.success? == true
  end

  test "filters noise event types" do
    events = [
      %{type: "file-history-snapshot", data: %{}, timestamp: nil},
      %{type: "progress", data: %{}, timestamp: nil},
      %{type: "user", data: %{"message" => %{"content" => "Hi"}}, timestamp: nil},
      %{type: "assistant", data: %{"message" => %{"content" => [%{"type" => "text", "text" => "Hello"}]}}, timestamp: nil}
    ]

    [turn] = Claude.parse_turns(events)
    assert turn.user_content == "Hi"
  end
end
