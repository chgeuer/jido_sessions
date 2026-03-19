defmodule JidoSessions.Tools.Search do
  @moduledoc "Content and file search operations."

  defmodule ContentArgs do
    @moduledoc "Arguments for grep/content search."
    @type t :: %__MODULE__{
            pattern: String.t(),
            path: String.t() | nil,
            file_type: String.t() | nil,
            case_sensitive?: boolean(),
            max_results: non_neg_integer() | nil
          }
    @enforce_keys [:pattern]
    defstruct [:pattern, :path, :file_type, :max_results, case_sensitive?: true]
  end

  defmodule ContentResult do
    @type t :: %__MODULE__{matches: String.t() | nil, match_count: non_neg_integer() | nil}
    defstruct [:matches, :match_count]
  end

  defmodule FilesArgs do
    @moduledoc "Arguments for glob/file search."
    @type t :: %__MODULE__{pattern: String.t(), path: String.t() | nil}
    @enforce_keys [:pattern]
    defstruct [:pattern, :path]
  end

  defmodule FilesResult do
    @type t :: %__MODULE__{files: [String.t()], file_count: non_neg_integer() | nil}
    defstruct [:file_count, files: []]
  end
end
