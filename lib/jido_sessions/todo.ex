defmodule JidoSessions.Todo do
  @moduledoc "Task tracking item extracted from a session."

  @type status :: :pending | :in_progress | :done | :blocked
  @type t :: %__MODULE__{
          todo_id: String.t(),
          title: String.t(),
          description: String.t() | nil,
          status: status(),
          depends_on: [String.t()]
        }

  @enforce_keys [:todo_id, :title]
  defstruct [:todo_id, :title, :description, status: :pending, depends_on: []]
end
