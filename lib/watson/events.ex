defmodule Watson.Events do
  @moduledoc false

  defmodule DevicesListed do
    @enforce_keys [:devices]
    defstruct [:devices]

    @type t() :: %__MODULE__{devices: [Watson.Capture.Device.t()]}
  end

  defmodule SessionStarted do
    @enforce_keys [:session_id, :session_dir, :started_at]
    defstruct [:session_id, :session_dir, :started_at]

    @type t() :: %__MODULE__{
            session_id: String.t(),
            session_dir: String.t(),
            started_at: DateTime.t()
          }
  end

  defmodule AudioChunkReceived do
    @enforce_keys [:session_id, :stream, :timestamp_us, :bytes]
    defstruct [:session_id, :stream, :timestamp_us, :bytes]

    @type t() :: %__MODULE__{
            session_id: String.t(),
            stream: Watson.Session.stream(),
            timestamp_us: non_neg_integer(),
            bytes: non_neg_integer()
          }
  end

  defmodule PartialTranscript do
    @enforce_keys [:session_id, :stream, :text, :artifact_path]
    defstruct [:session_id, :stream, :text, :artifact_path]

    @type t() :: %__MODULE__{
            session_id: String.t(),
            stream: Watson.Session.stream(),
            text: String.t(),
            artifact_path: String.t()
          }
  end

  defmodule FinalTranscript do
    @enforce_keys [:session_id, :stream, :text_path, :tsv_path]
    defstruct [:session_id, :stream, :text_path, :tsv_path]

    @type t() :: %__MODULE__{
            session_id: String.t(),
            stream: Watson.Session.stream() | :dialogue,
            text_path: String.t(),
            tsv_path: String.t() | nil
          }
  end

  defmodule SessionStopped do
    @enforce_keys [:session_id, :session_dir, :stopped_at]
    defstruct [:session_id, :session_dir, :stopped_at]

    @type t() :: %__MODULE__{
            session_id: String.t(),
            session_dir: String.t(),
            stopped_at: DateTime.t()
          }
  end

  defmodule HelperError do
    @enforce_keys [:reason]
    defstruct [:reason, :session_id]

    @type t() :: %__MODULE__{reason: String.t(), session_id: String.t() | nil}
  end
end
