defmodule JidoSessions.AgentParser do
  @moduledoc """
  Behaviour for agent session file parsers.

  Each coding agent (Copilot, Claude, Codex, Gemini, Pi) stores session data
  in different formats on disk. Implementations of this behaviour know how to:

  1. Find session directories/files in well-known locations
  2. Parse those files into a normalized `parsed_session` map

  The parsed output feeds into `JidoSessions.Sync` which persists via
  a `SessionStore` implementation.
  """

  @type session_id :: String.t()

  @type parsed_event :: %{
          type: String.t(),
          data: map(),
          timestamp: DateTime.t() | nil,
          sequence: non_neg_integer()
        }

  @type parsed_session :: %{
          session_id: session_id(),
          cwd: String.t() | nil,
          model: String.t() | nil,
          summary: String.t() | nil,
          title: String.t() | nil,
          git_root: String.t() | nil,
          branch: String.t() | nil,
          agent_version: String.t() | nil,
          started_at: DateTime.t() | nil,
          stopped_at: DateTime.t() | nil,
          events: [parsed_event()],
          artifacts: [JidoSessions.Artifact.t()],
          checkpoints: [JidoSessions.Checkpoint.t()],
          todos: [JidoSessions.Todo.t()]
        }

  @doc "Returns the agent type atom (:copilot, :claude, :codex, :gemini, :pi)."
  @callback agent_type() :: JidoSessions.Session.agent()

  @doc "Returns well-known directories where this agent stores sessions on the local machine."
  @callback well_known_dirs() :: [String.t()]

  @doc """
  Returns well-known directory patterns for remote hosts.
  Uses `~` for home directory expansion by the remote shell.
  """
  @callback remote_well_known_dirs() :: [String.t()]

  @doc """
  Discovers all sessions in the given base directory.
  Returns `[{session_id, file_or_dir_path}]`.
  """
  @callback discover_sessions(base_dir :: String.t()) :: [{session_id(), String.t()}]

  @doc """
  Parses a session file or directory into a normalized map.
  """
  @callback parse_session(path :: String.t()) :: {:ok, parsed_session()} | {:error, term()}

  @optional_callbacks [remote_well_known_dirs: 0]

  @doc "Discovers sessions across all given agent modules in their well-known dirs."
  def discover_local(modules) when is_list(modules) do
    Enum.flat_map(modules, fn mod ->
      mod.well_known_dirs()
      |> Enum.filter(&File.dir?/1)
      |> Enum.flat_map(fn dir ->
        mod.discover_sessions(dir)
        |> Enum.map(fn {sid, path} -> {mod.agent_type(), sid, path, dir} end)
      end)
    end)
  end
end
