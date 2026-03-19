defmodule JidoSessions.Tools.Skill do
  @moduledoc "Skill invocation."

  defmodule Args do
    @type t :: %__MODULE__{skill: String.t(), extra: map()}
    @enforce_keys [:skill]
    defstruct [:skill, extra: %{}]
  end

  defmodule Result do
    @type t :: %__MODULE__{output: String.t() | nil}
    defstruct [:output]
  end
end
