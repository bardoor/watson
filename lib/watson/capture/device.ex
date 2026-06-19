defmodule Watson.Capture.Device do
  @moduledoc false

  @enforce_keys [:id, :name, :is_default]
  defstruct [:id, :name, :is_default]

  @type t() :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          is_default: boolean()
        }
end
