defmodule JidoSessions.Parsers.CopilotTest do
  use ExUnit.Case, async: true

  alias JidoSessions.Parsers.Copilot
  alias JidoSessions.Tools

  test "parses user message + assistant response" do
    events = [
      %{type: "user.message", data: %{"content" => "Fix the bug"}, timestamp: nil},
      %{type: "assistant.message", data: %{"content" => "I'll fix it."}, timestamp: nil}
    ]

    [turn] = Copilot.parse_turns(events)
    assert turn.user_content == "Fix the bug"
    assert turn.assistant_content == "I'll fix it."
  end

  test "accumulates multiple assistant.message chunks" do
    events = [
      %{type: "user.message", data: %{"content" => "Hello"}, timestamp: nil},
      %{type: "assistant.message", data: %{"content" => "Hi "}, timestamp: nil},
      %{type: "assistant.message", data: %{"content" => "there!"}, timestamp: nil}
    ]

    [turn] = Copilot.parse_turns(events)
    assert turn.assistant_content == "Hi there!"
  end

  test "extracts reasoningText" do
    events = [
      %{type: "user.message", data: %{"content" => "Q"}, timestamp: nil},
      %{
        type: "assistant.message",
        data: %{"content" => "A", "reasoningText" => "Let me think..."},
        timestamp: nil
      }
    ]

    [turn] = Copilot.parse_turns(events)
    assert turn.reasoning =~ "Let me think"
  end

  test "merges tool.execution_start with tool.execution_complete" do
    events = [
      %{type: "user.message", data: %{"content" => "Run tests"}, timestamp: nil},
      %{
        type: "tool.execution_start",
        data: %{"toolCallId" => "c1", "toolName" => "bash", "arguments" => %{"command" => "mix test"}},
        timestamp: nil
      },
      %{
        type: "tool.execution_complete",
        data: %{"toolCallId" => "c1", "success" => true, "result" => "3 tests, 0 failures"},
        timestamp: nil
      },
      %{type: "assistant.message", data: %{"content" => "Tests pass!"}, timestamp: nil}
    ]

    [turn] = Copilot.parse_turns(events)
    assert length(turn.tool_calls) == 1

    [tc] = turn.tool_calls
    assert tc.tool == :shell
    assert %Tools.Shell.Args{command: "mix test"} = tc.arguments
    assert tc.success? == true
  end

  test "filters noise events" do
    events = [
      %{type: "session.start", data: %{}, timestamp: nil},
      %{type: "hook.start", data: %{}, timestamp: nil},
      %{type: "user.message", data: %{"content" => "Hi"}, timestamp: nil},
      %{type: "hook.end", data: %{}, timestamp: nil},
      %{type: "assistant.message", data: %{"content" => "Hello"}, timestamp: nil}
    ]

    [turn] = Copilot.parse_turns(events)
    assert turn.user_content == "Hi"
    assert turn.assistant_content == "Hello"
  end

  test "splits multiple turns on user messages" do
    events = [
      %{type: "user.message", data: %{"content" => "First"}, timestamp: nil},
      %{type: "assistant.message", data: %{"content" => "Reply 1"}, timestamp: nil},
      %{type: "user.message", data: %{"content" => "Second"}, timestamp: nil},
      %{type: "assistant.message", data: %{"content" => "Reply 2"}, timestamp: nil}
    ]

    turns = Copilot.parse_turns(events)
    assert length(turns) == 2
    assert Enum.at(turns, 0).user_content == "First"
    assert Enum.at(turns, 1).user_content == "Second"
  end

  test "parses usage from assistant.usage events" do
    events = [
      %{type: "user.message", data: %{"content" => "Q"}, timestamp: nil},
      %{type: "assistant.message", data: %{"content" => "A"}, timestamp: nil},
      %{
        type: "assistant.usage",
        data: %{
          "model" => "claude-sonnet-4",
          "inputTokens" => 1500,
          "outputTokens" => 300,
          "cost" => 0.01
        },
        timestamp: nil
      }
    ]

    [turn] = Copilot.parse_turns(events)
    assert turn.usage.model == "claude-sonnet-4"
    assert turn.usage.input_tokens == 1500
    assert turn.usage.output_tokens == 300
  end
end
