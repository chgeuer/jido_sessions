defmodule JidoSessions do
  @moduledoc """
  Canonical session data types and parsers for coding agent conversations.

  Supports Copilot, Claude, Codex, Gemini, and Pi agents with a unified
  data model for sessions, turns, tool calls, and artifacts.
  """

  alias JidoSessions.{Session, Turn}
  alias JidoSessions.Parsers

  @doc """
  Parses raw agent events into canonical `Turn` structs.

  ## Examples

      turns = JidoSessions.parse_turns(raw_events, :copilot)
      # => [%Turn{user_content: "Fix the bug", tool_calls: [...]}]
  """
  @spec parse_turns([map()], Session.agent()) :: [Turn.t()]
  def parse_turns(events, agent) do
    case agent do
      :copilot -> Parsers.Copilot.parse_turns(events)
      :claude -> Parsers.Claude.parse_turns(events)
      :codex -> Parsers.Codex.parse_turns(events)
      :gemini -> Parsers.Gemini.parse_turns(events)
      :pi -> Parsers.Pi.parse_turns(events)
    end
  end

  @doc """
  Generates a handoff document for a session.

  Returns `{:ok, %{session: summary, handoff: data, markdown: string}}` or
  `{:error, reason}`.
  """
  @spec generate_handoff(module(), term(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  defdelegate generate_handoff(store_mod, store, session_ref, opts \\ []),
    to: JidoSessions.Handoff,
    as: :generate

  @doc "Returns a takeover prompt instructing the new agent how to resume."
  @spec takeover_prompt(String.t()) :: String.t()
  defdelegate takeover_prompt(handoff_url), to: JidoSessions.Handoff
end
