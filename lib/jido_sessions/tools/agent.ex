defmodule JidoSessions.Tools.Agent do
  @moduledoc "Sub-agent / task management operations."

  defmodule CreateArgs do
    @type t :: %__MODULE__{
            agent_type: String.t(),
            name: String.t() | nil,
            description: String.t() | nil,
            prompt: String.t()
          }
    @enforce_keys [:prompt]
    defstruct [:agent_type, :name, :description, :prompt]
  end

  defmodule CreateResult do
    @type t :: %__MODULE__{agent_id: String.t() | nil, status: String.t() | nil}
    defstruct [:agent_id, :status]
  end

  defmodule ReadArgs do
    @type t :: %__MODULE__{agent_id: String.t()}
    @enforce_keys [:agent_id]
    defstruct [:agent_id]
  end

  defmodule ReadResult do
    @type t :: %__MODULE__{status: String.t() | nil, output: String.t() | nil}
    defstruct [:status, :output]
  end

  defmodule ListArgs do
    @type t :: %__MODULE__{}
    defstruct []
  end

  defmodule ListResult do
    @type t :: %__MODULE__{agents: [map()]}
    defstruct agents: []
  end
end
