defmodule JidoSessions.ToolNames do
  @moduledoc """
  Maps agent-specific tool names to canonical `ToolCall.tool()` atoms.

  Each coding agent uses different names for equivalent operations.
  This module normalizes them to a shared vocabulary.
  """

  alias JidoSessions.ToolCall

  @doc "Converts an agent-specific tool name string to a canonical tool atom."
  @spec canonicalize(String.t()) :: ToolCall.tool()
  def canonicalize(name) when is_binary(name) do
    case name do
      # Shell
      n when n in ~w[bash Bash shell_command run_shell_command exec_command shell] ->
        :shell

      n when n in ~w[read_bash BashOutput] ->
        :shell_read

      n when n in ~w[write_bash write_stdin] ->
        :shell_write

      n when n in ~w[stop_bash KillShell] ->
        :shell_stop

      "list_bash" ->
        :shell_list

      # File operations
      n when n in ~w[view show_file Read read_file read] ->
        :file_read

      n when n in ~w[create Write write_file write] ->
        :file_create

      n when n in ~w[edit Edit MultiEdit multiedit replace] ->
        :file_edit

      n when n in ~w[apply_patch ApplyPatch] ->
        :file_patch

      # Search
      n when n in ~w[grep Grep rg search_file_content] ->
        :search_content

      n when n in ~w[glob Glob list_directory list_files ls] ->
        :search_files

      "file_search" ->
        :search_content

      # User interaction
      n when n in ~w[ask_user AskUserQuestion request_user_input] ->
        :ask_user

      # Sub-agents
      n when n in ~w[task Task TaskCreate] ->
        :task_create

      n when n in ~w[read_agent TaskOutput] ->
        :task_read

      n when n in ~w[list_agents TaskList] ->
        :task_list

      # Web
      n when n in ~w[web_search WebSearch google_web_search] ->
        :web_search

      n when n in ~w[web_fetch WebFetch] ->
        :web_fetch

      # Planning & metadata
      n
      when n in ~w[report_intent ReportIntent EnterPlanMode ExitPlanMode update_plan fetch_copilot_cli_documentation] ->
        :intent

      n when n in ~w[update_todo TodoWrite TaskUpdate write_todos task_complete] ->
        :todo_update

      n when n in ~w[sql Sql] ->
        :sql

      n when n in ~w[store_memory] ->
        :memory

      n when n in ~w[skill Skill] ->
        :skill

      # GitHub
      n when is_binary(n) ->
        if String.starts_with?(n, "github-mcp-server-"), do: :github_api, else: :unknown
    end
  end
end
