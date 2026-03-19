defmodule JidoSessions.SessionStore.Memory do
  @moduledoc """
  In-memory SessionStore implementation backed by an Agent.

  Useful for testing and development. All data is lost when the process stops.

  ## Usage

      {:ok, store} = Memory.start_link()
      Memory.upsert_session(store, session)
      {:ok, session} = Memory.get_session(store, "session-id")
  """

  use Agent

  alias JidoSessions.Session

  defstruct sessions: %{},
            events: %{},
            artifacts: %{},
            checkpoints: %{},
            todos: %{},
            usage: %{}

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name)
    Agent.start_link(fn -> %__MODULE__{} end, name: name && {:via, Registry, name})
  end

  # ── Sessions ──

  def upsert_session(store, %Session{} = session) do
    Agent.update(store, fn state ->
      %{state | sessions: Map.put(state.sessions, session.id, session)}
    end)

    {:ok, session}
  end

  def get_session(store, id) do
    case Agent.get(store, fn state -> Map.get(state.sessions, id) end) do
      nil -> {:error, :not_found}
      session -> {:ok, session}
    end
  end

  def list_sessions(store, filters \\ []) do
    Agent.get(store, fn state ->
      sessions = Map.values(state.sessions)

      Enum.reduce(filters, sessions, fn
        {:agent, agent}, acc -> Enum.filter(acc, &(&1.agent == agent))
        {:status, status}, acc -> Enum.filter(acc, &(&1.status == status))
        _, acc -> acc
      end)
      |> Enum.sort_by(&(&1.started_at || ~U[1970-01-01 00:00:00Z]), {:desc, DateTime})
    end)
  end

  def delete_session(store, id) do
    Agent.update(store, fn state ->
      %{
        state
        | sessions: Map.delete(state.sessions, id),
          events: Map.delete(state.events, id),
          artifacts: Map.delete(state.artifacts, id),
          checkpoints: Map.delete(state.checkpoints, id),
          todos: Map.delete(state.todos, id),
          usage: Map.delete(state.usage, id)
      }
    end)

    :ok
  end

  def session_exists?(store, id) do
    Agent.get(store, fn state -> Map.has_key?(state.sessions, id) end)
  end

  # ── Events ──

  def insert_events(store, session_id, events) do
    Agent.update(store, fn state ->
      existing = Map.get(state.events, session_id, [])
      existing_sequences = MapSet.new(existing, & &1.sequence)

      new_events =
        Enum.reject(events, fn e -> MapSet.member?(existing_sequences, e.sequence) end)

      %{state | events: Map.put(state.events, session_id, existing ++ new_events)}
    end)

    {:ok, length(events)}
  end

  def get_events(store, session_id) do
    Agent.get(store, fn state ->
      state.events
      |> Map.get(session_id, [])
      |> Enum.sort_by(& &1.sequence)
    end)
  end

  def event_count(store, session_id) do
    Agent.get(store, fn state ->
      state.events |> Map.get(session_id, []) |> length()
    end)
  end

  # ── Artifacts ──

  def upsert_artifacts(store, session_id, artifacts) do
    Agent.update(store, fn state ->
      existing = Map.get(state.artifacts, session_id, [])

      merged =
        Enum.reduce(artifacts, existing, fn art, acc ->
          case Enum.find_index(acc, &(&1.path == art.path)) do
            nil -> acc ++ [art]
            idx -> List.replace_at(acc, idx, art)
          end
        end)

      %{state | artifacts: Map.put(state.artifacts, session_id, merged)}
    end)

    :ok
  end

  def get_artifacts(store, session_id) do
    Agent.get(store, fn state -> Map.get(state.artifacts, session_id, []) end)
  end

  # ── Checkpoints ──

  def insert_checkpoints(store, session_id, checkpoints) do
    Agent.update(store, fn state ->
      existing = Map.get(state.checkpoints, session_id, [])
      %{state | checkpoints: Map.put(state.checkpoints, session_id, existing ++ checkpoints)}
    end)

    :ok
  end

  def get_checkpoints(store, session_id) do
    Agent.get(store, fn state ->
      state.checkpoints
      |> Map.get(session_id, [])
      |> Enum.sort_by(& &1.number)
    end)
  end

  # ── Todos ──

  def upsert_todos(store, session_id, todos) do
    Agent.update(store, fn state ->
      existing = Map.get(state.todos, session_id, [])

      merged =
        Enum.reduce(todos, existing, fn todo, acc ->
          case Enum.find_index(acc, &(&1.todo_id == todo.todo_id)) do
            nil -> acc ++ [todo]
            idx -> List.replace_at(acc, idx, todo)
          end
        end)

      %{state | todos: Map.put(state.todos, session_id, merged)}
    end)

    :ok
  end

  def get_todos(store, session_id) do
    Agent.get(store, fn state -> Map.get(state.todos, session_id, []) end)
  end

  # ── Usage ──

  def insert_usage(store, session_id, entries) do
    Agent.update(store, fn state ->
      existing = Map.get(state.usage, session_id, [])
      %{state | usage: Map.put(state.usage, session_id, existing ++ entries)}
    end)

    :ok
  end

  def get_usage(store, session_id) do
    Agent.get(store, fn state -> Map.get(state.usage, session_id, []) end)
  end
end
