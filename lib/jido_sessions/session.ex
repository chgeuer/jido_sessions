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

  @doc "Creates a prefixed session ID like 'gh_abc123' or 'claude_abc123'."
  @spec prefixed_id(agent(), String.t()) :: String.t()
  def prefixed_id(agent, provider_id) do
    prefix =
      case agent do
        :copilot -> "gh"
        :claude -> "claude"
        :codex -> "codex"
        :gemini -> "gemini"
        :pi -> "pi"
        other -> to_string(other)
      end

    "#{prefix}_#{provider_id}"
  end

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
