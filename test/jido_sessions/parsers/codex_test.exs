defmodule JidoSessions.Parsers.CodexTest do
  use ExUnit.Case, async: true

  alias JidoSessions.Parsers.Codex

  test "parses user input_text and assistant output_text" do
    events = [
      %{
        type: "response_item",
        data: %{
          "payload" => %{
            "role" => "user",
            "content" => [%{"type" => "input_text", "text" => "Fix it"}]
          }
        },
        timestamp: nil
      },
      %{
        type: "response_item",
        data: %{
          "payload" => %{
            "role" => "assistant",
            "content" => [%{"type" => "output_text", "text" => "Done!"}]
          }
        },
        timestamp: nil
      }
    ]

    [turn] = Codex.parse_turns(events)
    assert turn.user_content == "Fix it"
    assert turn.assistant_content == "Done!"
  end

  test "parses function_call and function_call_output" do
    events = [
      %{
        type: "response_item",
        data: %{
          "payload" => %{
            "type" => "function_call",
            "name" => "shell_command",
            "call_id" => "c1",
            "arguments" => ~s({"command":["mix","test"]})
          }
        },
        timestamp: nil
      },
      %{
        type: "response_item",
        data: %{
          "payload" => %{
            "type" => "function_call_output",
            "call_id" => "c1",
            "output" => "3 tests, 0 failures"
          }
        },
        timestamp: nil
      }
    ]

    [turn] = Codex.parse_turns(events)
    assert length(turn.tool_calls) == 1
    [tc] = turn.tool_calls
    assert tc.tool == :shell
    assert tc.success? == true
  end

  test "parses reasoning payload" do
    events = [
      %{
        type: "response_item",
        data: %{
          "payload" => %{
            "type" => "reasoning",
            "text" => "Let me analyze this..."
          }
        },
        timestamp: nil
      }
    ]

    [turn] = Codex.parse_turns(events)
    assert turn.reasoning =~ "Let me analyze"
  end

  test "skips session_meta and event_msg" do
    events = [
      %{type: "session_meta", data: %{}, timestamp: nil},
      %{type: "event_msg", data: %{}, timestamp: nil},
      %{
        type: "response_item",
        data: %{
          "payload" => %{
            "type" => "reasoning",
            "text" => "Thinking"
          }
        },
        timestamp: nil
      }
    ]

    [turn] = Codex.parse_turns(events)
    assert turn.reasoning =~ "Thinking"
  end
end
