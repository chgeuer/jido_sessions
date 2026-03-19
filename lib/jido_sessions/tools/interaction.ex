defmodule JidoSessions.Tools.Interaction do
  @moduledoc "User interaction, intent reporting, todo management, memory, and SQL."

  defmodule AskUserArgs do
    @type t :: %__MODULE__{
            question: String.t(),
            choices: [String.t()],
            allow_freeform?: boolean()
          }
    @enforce_keys [:question]
    defstruct [:question, choices: [], allow_freeform?: true]
  end

  defmodule AskUserResult do
    @type t :: %__MODULE__{response: String.t() | nil}
    defstruct [:response]
  end

  defmodule IntentArgs do
    @type t :: %__MODULE__{intent: String.t()}
    @enforce_keys [:intent]
    defstruct [:intent]
  end

  defmodule TodoUpdateArgs do
    @type t :: %__MODULE__{
            todo_id: String.t(),
            title: String.t() | nil,
            status: String.t() | nil,
            description: String.t() | nil
          }
    @enforce_keys [:todo_id]
    defstruct [:todo_id, :title, :status, :description]
  end

  defmodule MemoryArgs do
    @type t :: %__MODULE__{
            subject: String.t(),
            fact: String.t(),
            reason: String.t() | nil
          }
    @enforce_keys [:subject, :fact]
    defstruct [:subject, :fact, :reason]
  end

  defmodule SqlArgs do
    @type t :: %__MODULE__{
            query: String.t(),
            database: String.t() | nil,
            description: String.t() | nil
          }
    @enforce_keys [:query]
    defstruct [:query, :database, :description]
  end

  defmodule SqlResult do
    @type t :: %__MODULE__{rows: [map()], row_count: non_neg_integer() | nil}
    defstruct [:row_count, rows: []]
  end

  defmodule EmptyResult do
    @moduledoc "Placeholder result for tools that have no meaningful return value."
    @type t :: %__MODULE__{}
    defstruct []
  end
end
