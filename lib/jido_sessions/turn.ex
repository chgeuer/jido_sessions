defmodule JidoSessions.Turn do
  @moduledoc "A single exchange: one user message + assistant response with tool calls."

  alias JidoSessions.{ToolCall, Usage}

  @type t :: %__MODULE__{
          index: non_neg_integer(),
          started_at: DateTime.t() | nil,
          user_content: String.t() | nil,
          user_attachments: [map()],
          reasoning: String.t() | nil,
          assistant_content: String.t() | nil,
          tool_calls: [ToolCall.t()],
          usage: Usage.t() | nil
        }

  defstruct [
    :started_at,
    :user_content,
    :reasoning,
    :assistant_content,
    :usage,
    index: 0,
    user_attachments: [],
    tool_calls: []
  ]
end
