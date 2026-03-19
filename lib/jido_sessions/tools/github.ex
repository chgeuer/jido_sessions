defmodule JidoSessions.Tools.GitHub do
  @moduledoc "GitHub API operations via MCP server."

  defmodule Args do
    @type t :: %__MODULE__{
            method: String.t(),
            owner: String.t() | nil,
            repo: String.t() | nil,
            query: String.t() | nil,
            extra: map()
          }
    @enforce_keys [:method]
    defstruct [:method, :owner, :repo, :query, extra: %{}]
  end

  defmodule Result do
    @type t :: %__MODULE__{data: map() | String.t() | nil}
    defstruct [:data]
  end
end
