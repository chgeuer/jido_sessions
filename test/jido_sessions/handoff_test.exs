defmodule JidoSessions.HandoffTest do
  use ExUnit.Case, async: true

  alias JidoSessions.SessionStore.Memory
  alias JidoSessions.{Session, Checkpoint, Todo}

  setup do
    {:ok, store} = Memory.start_link()

    session = %Session{
      id: "gh_test-handoff",
      agent: :copilot,
      cwd: "/home/user/project",
      branch: "main",
      model: "claude-sonnet-4",
      title: "Fix auth bug",
      summary: "Fixed the JWT verification issue"
    }

    Memory.upsert_session(store, session)

    events = [
      %{
        type: "user.message",
        data: %{"content" => "Fix the login bug"},
        timestamp: nil,
        sequence: 0
      },
      %{
        type: "tool.execution_start",
        data: %{
          "toolCallId" => "c1",
          "toolName" => "bash",
          "arguments" => %{"command" => "mix test"}
        },
        timestamp: nil,
        sequence: 1
      },
      %{
        type: "tool.execution_complete",
        data: %{"toolCallId" => "c1", "success" => true, "result" => "3 tests, 0 failures"},
        timestamp: nil,
        sequence: 2
      },
      %{
        type: "assistant.message",
        data: %{"content" => "All tests pass!"},
        timestamp: nil,
        sequence: 3
      }
    ]

    Memory.insert_events(store, "gh_test-handoff", events)

    Memory.upsert_todos(store, "gh_test-handoff", [
      %Todo{todo_id: "fix-auth", title: "Fix auth", status: :done},
      %Todo{todo_id: "add-tests", title: "Add tests", status: :pending}
    ])

    Memory.insert_checkpoints(store, "gh_test-handoff", [
      %Checkpoint{number: 1, title: "Initial", filename: "001.md", content: "snapshot"}
    ])

    %{store: store}
  end

  test "generates handoff markdown", %{store: store} do
    {:ok, markdown} = JidoSessions.generate_handoff(Memory, store, "gh_test-handoff")

    assert markdown =~ "Fix auth bug"
    assert markdown =~ "copilot"
    assert markdown =~ "mix test"
    assert markdown =~ "Outstanding Work"
    assert markdown =~ "Add tests"
    assert markdown =~ "Checkpoints"
  end

  test "returns error for missing session", %{store: store} do
    assert {:error, :not_found} = JidoSessions.generate_handoff(Memory, store, "nope")
  end
end
