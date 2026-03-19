defmodule JidoSessions.Parsers.PiTest do
  use ExUnit.Case, async: true

  alias JidoSessions.Parsers.Pi

  test "parses user + assistant with thinking and text" do
    events = [
      %{
        type: "message",
        data: %{
          "message" => %{
            "role" => "user",
            "content" => [%{"type" => "text", "text" => "Fix the bug"}]
          }
        },
        timestamp: nil
      },
      %{
        type: "message",
        data: %{
          "message" => %{
            "role" => "assistant",
            "content" => [
              %{"type" => "thinking", "thinking" => "Let me check..."},
              %{"type" => "text", "text" => "Found the issue."}
            ]
          }
        },
        timestamp: nil
      }
    ]

    [turn] = Pi.parse_turns(events)
    assert turn.user_content == "Fix the bug"
    assert turn.reasoning =~ "Let me check"
    assert turn.assistant_content == "Found the issue."
  end

  test "parses toolCall + toolResult" do
    events = [
      %{
        type: "message",
        data: %{
          "message" => %{
            "role" => "user",
            "content" => [%{"type" => "text", "text" => "Run tests"}]
          }
        },
        timestamp: nil
      },
      %{
        type: "message",
        data: %{
          "message" => %{
            "role" => "assistant",
            "content" => [
              %{
                "type" => "toolCall",
                "name" => "bash",
                "id" => "tc1",
                "arguments" => %{"command" => "mix test"}
              }
            ]
          }
        },
        timestamp: nil
      },
      %{
        type: "message",
        data: %{
          "message" => %{
            "role" => "toolResult",
            "toolCallId" => "tc1",
            "toolName" => "bash",
            "isError" => false,
            "content" => [%{"type" => "text", "text" => "3 tests, 0 failures"}]
          }
        },
        timestamp: nil
      }
    ]

    [turn] = Pi.parse_turns(events)
    assert length(turn.tool_calls) == 1
    [tc] = turn.tool_calls
    assert tc.tool == :shell
    assert tc.success? == true
  end

  test "skips session lifecycle events" do
    events = [
      %{type: "session", data: %{}, timestamp: nil},
      %{type: "model_change", data: %{}, timestamp: nil},
      %{
        type: "message",
        data: %{
          "message" => %{
            "role" => "user",
            "content" => [%{"type" => "text", "text" => "Hi"}]
          }
        },
        timestamp: nil
      },
      %{
        type: "message",
        data: %{
          "message" => %{
            "role" => "assistant",
            "content" => [%{"type" => "text", "text" => "Hello!"}]
          }
        },
        timestamp: nil
      }
    ]

    [turn] = Pi.parse_turns(events)
    assert turn.user_content == "Hi"
  end
end
