defmodule Watson.Capture.Protocol do
  @moduledoc false

  alias Watson.Capture.Device

  @command_json 0x01
  @event_json 0x02
  @audio_chunk 0x03

  @type helper_event() ::
          {:devices, [Device.t()]}
          | {:session_started, String.t()}
          | {:session_stopped, String.t()}
          | {:helper_error, String.t()}

  @spec encode_command(atom(), map()) :: binary()
  def encode_command(command, payload \\ %{}) do
    body =
      payload
      |> Map.put(:command, Atom.to_string(command))
      |> JSON.encode_to_iodata!()

    IO.iodata_to_binary([<<@command_json>>, body])
  end

  @spec decode_frame(binary()) ::
          {:ok, helper_event()}
          | {:ok, {:audio_chunk, Watson.Session.stream(), non_neg_integer(), binary()}}
          | {:error, term()}
  def decode_frame(<<@event_json, json::binary>>) do
    with {:ok, decoded} <- JSON.decode(json),
         {:ok, event} <- decode_event(decoded) do
      {:ok, event}
    end
  end

  def decode_frame(<<@audio_chunk, stream_id, timestamp_us::unsigned-64, pcm::binary>>) do
    with {:ok, stream} <- decode_stream(stream_id),
         :ok <- validate_timestamp(timestamp_us) do
      {:ok, {:audio_chunk, stream, timestamp_us, pcm}}
    end
  end

  def decode_frame(<<type, _::binary>>) do
    {:error, {:unknown_frame_type, type}}
  end

  def decode_frame(_payload) do
    {:error, :invalid_frame}
  end

  defp decode_event(%{"event" => "devices", "devices" => devices}) when is_list(devices) do
    decoded =
      Enum.map(devices, fn %{"id" => id, "name" => name, "is_default" => is_default} ->
        %Device{id: id, name: name, is_default: is_default}
      end)

    {:ok, {:devices, decoded}}
  rescue
    _ -> {:error, :invalid_devices_event}
  end

  defp decode_event(%{"event" => "session_started", "session_id" => session_id}) do
    {:ok, {:session_started, session_id}}
  end

  defp decode_event(%{"event" => "session_stopped", "session_id" => session_id}) do
    {:ok, {:session_stopped, session_id}}
  end

  defp decode_event(%{"event" => "error", "reason" => reason}) do
    {:ok, {:helper_error, reason}}
  end

  defp decode_event(_event) do
    {:error, :unknown_event}
  end

  defp decode_stream(1), do: {:ok, :mic}
  defp decode_stream(2), do: {:ok, :system}
  defp decode_stream(stream_id), do: {:error, {:invalid_stream_id, stream_id}}

  defp validate_timestamp(timestamp_us) when is_integer(timestamp_us) and timestamp_us >= 0, do: :ok
  defp validate_timestamp(_timestamp_us), do: {:error, :invalid_timestamp}
end
