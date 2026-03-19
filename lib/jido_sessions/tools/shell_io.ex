defmodule JidoSessions.Tools.ShellIO do
  @moduledoc "Interactive shell I/O: read output, write input, stop, list sessions."

  defmodule ReadArgs do
    @type t :: %__MODULE__{session_id: String.t(), timeout_ms: non_neg_integer() | nil}
    @enforce_keys [:session_id]
    defstruct [:session_id, :timeout_ms]
  end

  defmodule WriteArgs do
    @type t :: %__MODULE__{session_id: String.t(), input: String.t()}
    @enforce_keys [:session_id, :input]
    defstruct [:session_id, :input]
  end

  defmodule StopArgs do
    @type t :: %__MODULE__{session_id: String.t()}
    @enforce_keys [:session_id]
    defstruct [:session_id]
  end

  defmodule ListArgs do
    @type t :: %__MODULE__{}
    defstruct []
  end

  defmodule Result do
    @type t :: %__MODULE__{output: String.t() | nil}
    defstruct [:output]
  end
end
