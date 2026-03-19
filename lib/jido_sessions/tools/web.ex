defmodule JidoSessions.Tools.Web do
  @moduledoc "Web search and fetch operations."

  defmodule SearchArgs do
    @type t :: %__MODULE__{query: String.t()}
    @enforce_keys [:query]
    defstruct [:query]
  end

  defmodule SearchResult do
    @type t :: %__MODULE__{content: String.t() | nil, sources: [map()]}
    defstruct [:content, sources: []]
  end

  defmodule FetchArgs do
    @type t :: %__MODULE__{url: String.t(), max_length: non_neg_integer() | nil}
    @enforce_keys [:url]
    defstruct [:url, :max_length]
  end

  defmodule FetchResult do
    @type t :: %__MODULE__{content: String.t() | nil, content_type: String.t() | nil}
    defstruct [:content, :content_type]
  end
end
