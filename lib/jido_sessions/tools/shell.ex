defmodule JidoSessions.Tools.Shell do
  @moduledoc "Shell command execution."

  defmodule Args do
    @type t :: %__MODULE__{
            command: String.t(),
            workdir: String.t() | nil,
            description: String.t() | nil,
            timeout_ms: non_neg_integer() | nil
          }
    @enforce_keys [:command]
    defstruct [:command, :workdir, :description, :timeout_ms]
  end

  defmodule Result do
    @type t :: %__MODULE__{output: String.t() | nil, exit_status: integer() | nil}
    defstruct [:output, :exit_status]
  end
end
