defmodule JidoSessions.SessionStore.MemoryTest do
  use ExUnit.Case, async: true

  alias JidoSessions.SessionStore.Memory
  alias JidoSessions.{Session, Artifact, Checkpoint, Todo, Usage}

  setup do
    {:ok, store} = Memory.start_link()
    %{store: store}
  end

  describe "sessions" do
    test "upsert and get", %{store: store} do
      session = %Session{id: "test-1", agent: :copilot, cwd: "/tmp"}
      {:ok, _} = Memory.upsert_session(store, session)
      {:ok, got} = Memory.get_session(store, "test-1")
      assert got.id == "test-1"
      assert got.agent == :copilot
    end

    test "get returns not_found for missing", %{store: store} do
      assert {:error, :not_found} = Memory.get_session(store, "nope")
    end

    test "list_sessions returns all", %{store: store} do
      Memory.upsert_session(store, %Session{id: "s1", agent: :copilot})
      Memory.upsert_session(store, %Session{id: "s2", agent: :claude})
      assert length(Memory.list_sessions(store)) == 2
    end

    test "list_sessions filters by agent", %{store: store} do
      Memory.upsert_session(store, %Session{id: "s1", agent: :copilot})
      Memory.upsert_session(store, %Session{id: "s2", agent: :claude})
      assert length(Memory.list_sessions(store, agent: :copilot)) == 1
    end

    test "delete removes session and related data", %{store: store} do
      Memory.upsert_session(store, %Session{id: "s1", agent: :copilot})
      Memory.insert_events(store, "s1", [%{type: "user.message", data: %{}, sequence: 0}])
      :ok = Memory.delete_session(store, "s1")
      assert {:error, :not_found} = Memory.get_session(store, "s1")
      assert Memory.get_events(store, "s1") == []
    end

    test "session_exists?", %{store: store} do
      refute Memory.session_exists?(store, "s1")
      Memory.upsert_session(store, %Session{id: "s1", agent: :copilot})
      assert Memory.session_exists?(store, "s1")
    end
  end

  describe "events" do
    test "insert and retrieve in sequence order", %{store: store} do
      events = [
        %{type: "a", data: %{}, sequence: 2, timestamp: nil},
        %{type: "b", data: %{}, sequence: 0, timestamp: nil},
        %{type: "c", data: %{}, sequence: 1, timestamp: nil}
      ]

      {:ok, 3} = Memory.insert_events(store, "s1", events)
      got = Memory.get_events(store, "s1")
      assert Enum.map(got, & &1.sequence) == [0, 1, 2]
    end

    test "deduplicates by sequence", %{store: store} do
      Memory.insert_events(store, "s1", [%{type: "a", data: %{}, sequence: 0, timestamp: nil}])
      Memory.insert_events(store, "s1", [%{type: "b", data: %{}, sequence: 0, timestamp: nil}])
      assert Memory.event_count(store, "s1") == 1
    end
  end

  describe "artifacts" do
    test "upsert and get", %{store: store} do
      art = %Artifact{path: "plan.md", artifact_type: :plan, content: "# Plan"}
      :ok = Memory.upsert_artifacts(store, "s1", [art])
      assert [%Artifact{path: "plan.md"}] = Memory.get_artifacts(store, "s1")
    end

    test "upsert replaces by path", %{store: store} do
      Memory.upsert_artifacts(store, "s1", [
        %Artifact{path: "p.md", artifact_type: :plan, content: "v1"}
      ])

      Memory.upsert_artifacts(store, "s1", [
        %Artifact{path: "p.md", artifact_type: :plan, content: "v2"}
      ])

      [art] = Memory.get_artifacts(store, "s1")
      assert art.content == "v2"
    end
  end

  describe "checkpoints" do
    test "insert and get sorted by number", %{store: store} do
      Memory.insert_checkpoints(store, "s1", [
        %Checkpoint{number: 2, title: "B", filename: "b.md", content: "b"},
        %Checkpoint{number: 1, title: "A", filename: "a.md", content: "a"}
      ])

      cps = Memory.get_checkpoints(store, "s1")
      assert Enum.map(cps, & &1.number) == [1, 2]
    end
  end

  describe "todos" do
    test "upsert replaces by todo_id", %{store: store} do
      Memory.upsert_todos(store, "s1", [%Todo{todo_id: "t1", title: "v1"}])
      Memory.upsert_todos(store, "s1", [%Todo{todo_id: "t1", title: "v2"}])
      [todo] = Memory.get_todos(store, "s1")
      assert todo.title == "v2"
    end
  end

  describe "usage" do
    test "insert and get", %{store: store} do
      Memory.insert_usage(store, "s1", [%Usage{model: "gpt-4", input_tokens: 100}])
      [u] = Memory.get_usage(store, "s1")
      assert u.model == "gpt-4"
    end
  end
end
