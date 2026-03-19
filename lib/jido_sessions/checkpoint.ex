defmodule JidoSessions.Checkpoint do
  @moduledoc "Compaction snapshot preserving context across token limit boundaries."

  @type t :: %__MODULE__{
          number: non_neg_integer(),
          title: String.t(),
          filename: String.t(),
          content: String.t()
        }

  @enforce_keys [:number, :title, :filename, :content]
  defstruct [:number, :title, :filename, :content]
end
