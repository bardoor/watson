defmodule Watson.Transcription.StreamWorker do
  @moduledoc false

  use GenServer

  alias Watson.Audio.WavWriter
  alias Watson.Events
  alias Watson.Transcription.MlxWhisper

  defstruct [
    :session_id,
    :stream,
    :wav_writer,
    :partial_txt_path,
    :language,
    :model,
    :cadence_us,
    :overlap_ms,
    last_snapshot_us: nil,
    last_text: ""
  ]

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @spec notify_appended(pid(), non_neg_integer()) :: :ok
  def notify_appended(pid, timestamp_us) do
    GenServer.cast(pid, {:notify_appended, timestamp_us})
  end

  @impl true
  def init(opts) do
    cadence_ms = Keyword.fetch!(opts, :cadence_ms)

    {:ok,
     %__MODULE__{
       session_id: Keyword.fetch!(opts, :session_id),
       stream: Keyword.fetch!(opts, :stream),
       wav_writer: Keyword.fetch!(opts, :wav_writer),
       partial_txt_path: Keyword.fetch!(opts, :partial_txt_path),
       language: Keyword.fetch!(opts, :language),
       model: Keyword.fetch!(opts, :model),
       cadence_us: cadence_ms * 1_000,
       overlap_ms: Keyword.fetch!(opts, :overlap_ms)
     }}
  end

  @impl true
  def handle_cast({:notify_appended, timestamp_us}, %__MODULE__{last_snapshot_us: nil} = state) do
    {:noreply, %{state | last_snapshot_us: timestamp_us}}
  end

  @impl true
  def handle_cast({:notify_appended, timestamp_us}, state) do
    if should_snapshot?(state, timestamp_us) do
      state = maybe_publish_partial(state, timestamp_us)
      {:noreply, %{state | last_snapshot_us: timestamp_us}}
    else
      {:noreply, state}
    end
  end
  defp should_snapshot?(state, timestamp_us) do
    timestamp_us - state.last_snapshot_us >= state.cadence_us
  end

  defp maybe_publish_partial(state, timestamp_us) do
    snapshot_dir = Path.dirname(state.partial_txt_path)
    snapshot_path = Path.join(snapshot_dir, "#{state.stream}_partial_snapshot_#{timestamp_us}.wav")

    with :ok <- WavWriter.snapshot(state.wav_writer, snapshot_path),
         {:ok, result} <-
           MlxWhisper.transcribe(
             audio_path: snapshot_path,
             output_dir: snapshot_dir,
             output_name: "#{state.stream}_transcript_partial_snapshot",
             model: state.model,
             language: state.language
           ),
         {:ok, text} <- File.read(result.txt_path) do
      File.rm(snapshot_path)
      maybe_write_partial(state, text)
    else
      _ -> state
    end
  end

  defp maybe_write_partial(state, text) do
    text = String.trim(text)

    cond do
      text == "" ->
        state

      text == state.last_text ->
        state

      String.starts_with?(text, state.last_text) ->
        suffix = text |> String.replace_prefix(state.last_text, "") |> String.trim()
        publish_partial(state, text, suffix)

      true ->
        publish_partial(state, text, text)
    end
  end

  defp publish_partial(state, full_text, emitted_text) do
    if emitted_text != "" do
      File.write!(state.partial_txt_path, full_text <> "\n")

      Watson.EventBus.publish(%Events.PartialTranscript{
        session_id: state.session_id,
        stream: state.stream,
        text: emitted_text,
        artifact_path: state.partial_txt_path
      })
    end

    %{state | last_text: full_text}
  end
end
