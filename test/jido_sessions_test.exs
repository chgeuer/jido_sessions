defmodule JidoSessionsTest do
  use ExUnit.Case

  test "parse_turns/2 dispatches to agent parsers" do
    # Minimal copilot event sequence
    events = [
      %{type: "user.message", data: %{"content" => "Hello"}, timestamp: nil},
      %{type: "assistant.message", data: %{"content" => "Hi there!"}, timestamp: nil}
    ]

    turns = JidoSessions.parse_turns(events, :copilot)
    assert is_list(turns)
    assert length(turns) >= 1

    turn = List.first(turns)
    assert %JidoSessions.Turn{} = turn
    assert turn.user_content == "Hello"
    assert turn.assistant_content == "Hi there!"
  end
end
