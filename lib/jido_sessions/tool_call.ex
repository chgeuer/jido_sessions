defmodule JidoSessions.ToolCall do
  @moduledoc """
  A single tool invocation with typed arguments and result.

  The `tool` field is a canonical atom that determines which argument/result
  struct type applies. See `JidoSessions.Tools` for all tool modules.
  """

  @type tool ::
          :shell
          | :shell_read
          | :shell_write
          | :shell_stop
          | :shell_list
          | :file_read
          | :file_create
          | :file_edit
          | :file_patch
          | :search_content
          | :search_files
          | :ask_user
          | :task_create
          | :task_read
          | :task_list
          | :web_search
          | :web_fetch
          | :intent
          | :todo_update
          | :sql
          | :memory
          | :skill
          | :github_api
          | :unknown

  @type t :: %__MODULE__{
          id: String.t() | nil,
          tool: tool(),
          arguments: struct() | map(),
          result: struct() | map() | nil,
          started_at: DateTime.t() | nil,
          completed_at: DateTime.t() | nil,
          success?: boolean() | nil
        }

  @enforce_keys [:tool]
  defstruct [
    :id,
    :tool,
    :result,
    :started_at,
    :completed_at,
    :success?,
    arguments: %{}
  ]
end
