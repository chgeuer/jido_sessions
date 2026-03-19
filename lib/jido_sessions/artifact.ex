defmodule JidoSessions.Artifact do
  @moduledoc "A file or data blob associated with a session."

  @type artifact_type :: :plan | :workspace | :file | :session_db_dump | :codex_thread_meta
  @type t :: %__MODULE__{
          path: String.t(),
          artifact_type: artifact_type(),
          content: String.t(),
          content_hash: String.t() | nil,
          size: non_neg_integer()
        }

  @enforce_keys [:path, :artifact_type, :content]
  defstruct [:path, :artifact_type, :content, :content_hash, size: 0]
end
