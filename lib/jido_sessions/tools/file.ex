defmodule JidoSessions.Tools.File do
  @moduledoc "File operations: read, create, edit, patch."

  defmodule ReadArgs do
    @type t :: %__MODULE__{path: String.t(), line_range: {non_neg_integer(), integer()} | nil}
    @enforce_keys [:path]
    defstruct [:path, :line_range]
  end

  defmodule ReadResult do
    @type t :: %__MODULE__{content: String.t() | nil, size: non_neg_integer() | nil}
    defstruct [:content, :size]
  end

  defmodule CreateArgs do
    @type t :: %__MODULE__{path: String.t(), content: String.t()}
    @enforce_keys [:path, :content]
    defstruct [:path, :content]
  end

  defmodule EditArgs do
    @type t :: %__MODULE__{path: String.t(), old_text: String.t(), new_text: String.t()}
    @enforce_keys [:path, :old_text, :new_text]
    defstruct [:path, :old_text, :new_text]
  end

  defmodule PatchArgs do
    @type t :: %__MODULE__{patch: String.t(), base_path: String.t() | nil}
    @enforce_keys [:patch]
    defstruct [:patch, :base_path]
  end

  defmodule PatchResult do
    @type t :: %__MODULE__{files_changed: [String.t()]}
    defstruct [files_changed: []]
  end

  defmodule WriteResult do
    @type t :: %__MODULE__{}
    defstruct []
  end
end
