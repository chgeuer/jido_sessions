defmodule JidoSessions.Session do
  @moduledoc "Root aggregate representing one human-agent conversation."

  @type agent :: :copilot | :claude | :codex | :gemini | :pi
  @type source :: :live | :imported
  @type status :: :starting | :idle | :thinking | :tool_running | :stopped

  @type t :: %__MODULE__{
          id: String.t(),
          agent: agent(),
          source: source(),
          status: status(),
          cwd: String.t() | nil,
          git_root: String.t() | nil,
          branch: String.t() | nil,
          title: String.t() | nil,
          summary: String.t() | nil,
          model: String.t() | nil,
          started_at: DateTime.t() | nil,
          stopped_at: DateTime.t() | nil,
          hostname: String.t() | nil,
          agent_version: String.t() | nil
        }

  @enforce_keys [:id, :agent]
  defstruct [
    :id,
    :agent,
    :cwd,
    :git_root,
    :branch,
    :title,
    :summary,
    :model,
    :started_at,
    :stopped_at,
    :hostname,
    :agent_version,
    source: :imported,
    status: :stopped
  ]
end
