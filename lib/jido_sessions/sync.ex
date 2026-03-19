defmodule JidoSessions.Sync do
  @moduledoc """
  Session discovery and import orchestration.

  Discovers sessions on disk using agent-specific well-known directories,
  parses them into canonical types, and persists via a SessionStore implementation.
  """

  alias JidoSessions.Session

  @type agent_module :: module()
  @type store :: pid() | atom() | {module(), term()}
  @type import_stats :: %{
          imported: non_neg_integer(),
          updated: non_neg_integer(),
          skipped: non_neg_integer(),
          errors: non_neg_integer()
        }

  @doc """
  Discovers and imports sessions from well-known directories for the given agents.

  `store_mod` is the SessionStore implementation module, `store` is the store
  reference (pid for Memory, module for DB-backed stores).
  """
  @spec import_all(module(), term(), keyword()) :: import_stats()
  def import_all(store_mod, store, opts \\ []) do
    agents = Keyword.get(opts, :agents, [])

    agents
    |> Enum.flat_map(fn {agent_atom, mod} ->
      discover(mod)
      |> Enum.map(fn {session_id, path} -> {agent_atom, mod, session_id, path} end)
    end)
    |> Enum.reduce(%{imported: 0, updated: 0, skipped: 0, errors: 0}, fn
      {agent_atom, mod, session_id, path}, stats ->
        case import_session(store_mod, store, agent_atom, mod, session_id, path) do
          {:ok, :imported} -> %{stats | imported: stats.imported + 1}
          {:ok, :updated} -> %{stats | updated: stats.updated + 1}
          {:error, _} -> %{stats | errors: stats.errors + 1}
        end
    end)
  end

  @doc """
  Discovers sessions in well-known directories for a given agent module.
  Returns `[{session_id, path}]`.
  """
  @spec discover(module()) :: [{String.t(), String.t()}]
  def discover(agent_mod) do
    agent_mod.well_known_dirs()
    |> Enum.filter(&File.dir?/1)
    |> Enum.flat_map(&agent_mod.discover_sessions/1)
  end

  @doc """
  Imports a single session from disk into the store.
  """
  @spec import_session(module(), term(), atom(), module(), String.t(), String.t()) ::
          {:ok, :imported | :updated | :skipped} | {:error, term()}
  def import_session(store_mod, store, agent_atom, agent_mod, session_id, path) do
    prefixed_id = Session.prefixed_id(agent_atom, session_id)

    case agent_mod.parse_session(path) do
      {:ok, parsed} ->
        session = %Session{
          id: prefixed_id,
          agent: agent_atom,
          source: :imported,
          status: :stopped,
          cwd: parsed.cwd,
          git_root: parsed.git_root,
          branch: parsed.branch,
          title: parsed.title,
          summary: parsed.summary,
          model: parsed.model,
          started_at: parsed.started_at,
          stopped_at: parsed.stopped_at,
          agent_version: parsed.agent_version
        }

        exists? = store_mod.session_exists?(store, prefixed_id)
        store_mod.upsert_session(store, session)

        if parsed.events && parsed.events != [] do
          store_mod.insert_events(store, prefixed_id, parsed.events)
        end

        if function_exported?(agent_mod, :parse_artifacts, 1) do
          case agent_mod.parse_artifacts(path) do
            artifacts when is_list(artifacts) and artifacts != [] ->
              store_mod.upsert_artifacts(store, prefixed_id, artifacts)

            _ ->
              :ok
          end
        end

        if function_exported?(agent_mod, :parse_checkpoints, 1) do
          case agent_mod.parse_checkpoints(path) do
            checkpoints when is_list(checkpoints) and checkpoints != [] ->
              store_mod.insert_checkpoints(store, prefixed_id, checkpoints)

            _ ->
              :ok
          end
        end

        if function_exported?(agent_mod, :parse_todos, 1) do
          case agent_mod.parse_todos(path) do
            todos when is_list(todos) and todos != [] ->
              store_mod.upsert_todos(store, prefixed_id, todos)

            _ ->
              :ok
          end
        end

        {:ok, if(exists?, do: :updated, else: :imported)}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
