defmodule JidoSessions.Usage do
  @moduledoc "Token and cost accounting for a single model invocation."

  @type t :: %__MODULE__{
          model: String.t() | nil,
          input_tokens: non_neg_integer(),
          output_tokens: non_neg_integer(),
          cache_read_tokens: non_neg_integer(),
          cache_write_tokens: non_neg_integer(),
          cost: float() | nil,
          duration_ms: non_neg_integer() | nil,
          initiator: String.t() | nil
        }

  defstruct [
    :model,
    :cost,
    :duration_ms,
    :initiator,
    input_tokens: 0,
    output_tokens: 0,
    cache_read_tokens: 0,
    cache_write_tokens: 0
  ]
end
