defmodule JidoSessions.SessionStore do
  @moduledoc """
  Behaviour for session persistence backends.

  Implementations provide storage for sessions, events, artifacts, checkpoints,
  todos, and usage entries. The library's sync engine and handoff modules
  use this behaviour to read and write session data without coupling to any
  specific database.

  ## Implementing

      defmodule MyApp.SessionStore do
        @behaviour JidoSessions.SessionStore

        @impl true
        def upsert_session(session), do: ...
        # ...
      end
  """

  alias JidoSessions.{Session, Artifact, Checkpoint, Todo, Usage}

  @type filter :: keyword()
  @type raw_event :: %{
          type: String.t(),
          data: map(),
          timestamp: DateTime.t() | nil,
          sequence: non_neg_integer()
        }

  @callback upsert_session(Session.t()) :: {:ok, Session.t()} | {:error, term()}
  @callback get_session(String.t()) :: {:ok, Session.t()} | {:error, :not_found}
  @callback list_sessions(filter()) :: [Session.t()]
  @callback delete_session(String.t()) :: :ok | {:error, term()}
  @callback session_exists?(String.t()) :: boolean()

  @callback insert_events(String.t(), [raw_event()]) :: {:ok, non_neg_integer()}
  @callback get_events(String.t()) :: [raw_event()]
  @callback event_count(String.t()) :: non_neg_integer()

  @callback upsert_artifacts(String.t(), [Artifact.t()]) :: :ok
  @callback get_artifacts(String.t()) :: [Artifact.t()]

  @callback insert_checkpoints(String.t(), [Checkpoint.t()]) :: :ok
  @callback get_checkpoints(String.t()) :: [Checkpoint.t()]

  @callback upsert_todos(String.t(), [Todo.t()]) :: :ok
  @callback get_todos(String.t()) :: [Todo.t()]

  @callback insert_usage(String.t(), [Usage.t()]) :: :ok
  @callback get_usage(String.t()) :: [Usage.t()]
end
