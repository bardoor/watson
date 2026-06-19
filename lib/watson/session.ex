defmodule Watson.Session do
  @moduledoc false

  use GenServer

  alias Watson.Audio.WavWriter
  alias Watson.Events
  alias Watson.SessionPaths
  alias Watson.Transcription.MlxWhisper
  alias Watson.Transcription.Postprocessor
  alias Watson.Transcription.Postprocessor.TranscriptInput
  alias Watson.Transcription.StreamWorker

  @type stream() :: :mic | :system
  @type status() :: %{active?: boolean(), session_id: String.t() | nil, session_dir: String.t() | nil}

  defstruct [
    :session_id,
    :paths,
    :helper_module,
    :microphone_id,
    :language,
    :model,
    :started_at,
    :start_result,
    :mic_writer,
    :system_writer,
    :mic_worker,
    :system_worker,
    start_waiters: []
  ]

  @spec start_link(map()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @spec await_started(pid()) :: {:ok, status()} | {:error, term()}
  def await_started(pid) do
    GenServer.call(pid, :await_started, 30_000)
  end

  @spec stop(pid()) :: :ok | {:error, term()}
  def stop(pid) do
    GenServer.call(pid, :stop, :infinity)
  end

  @impl true
  def init(opts) do
    recordings_dir = Keyword.fetch!(opts, :recordings_dir)
    paths = SessionPaths.create!(recordings_dir)
    session_id = Path.basename(paths.session_dir)
    language = Keyword.fetch!(opts, :language)
    model = Keyword.fetch!(opts, :model)
    helper_module = Keyword.fetch!(opts, :helper_module)

    {:ok, mic_writer} = WavWriter.start_link(path: paths.mic_wav, sample_rate: 48_000, channels: 1)
    {:ok, system_writer} = WavWriter.start_link(path: paths.system_wav, sample_rate: 48_000, channels: 2)

    {:ok, mic_worker} =
      StreamWorker.start_link(
        session_id: session_id,
        stream: :mic,
        wav_writer: mic_writer,
        partial_txt_path: paths.mic_partial_txt,
        language: language,
        model: model,
        cadence_ms: Application.fetch_env!(:watson, :transcription_cadence_ms),
        overlap_ms: Application.fetch_env!(:watson, :transcription_overlap_ms)
      )

    {:ok, system_worker} =
      StreamWorker.start_link(
        session_id: session_id,
        stream: :system,
        wav_writer: system_writer,
        partial_txt_path: paths.system_partial_txt,
        language: language,
        model: model,
        cadence_ms: Application.fetch_env!(:watson, :transcription_cadence_ms),
        overlap_ms: Application.fetch_env!(:watson, :transcription_overlap_ms)
      )

    state = %__MODULE__{
      session_id: session_id,
      paths: paths,
      helper_module: helper_module,
      microphone_id: Keyword.get(opts, :microphone_id),
      language: language,
      model: model,
      started_at: DateTime.utc_now(),
      start_result: nil,
      start_waiters: [],
      mic_writer: mic_writer,
      system_writer: system_writer,
      mic_worker: mic_worker,
      system_worker: system_worker
    }

    {:ok, state, {:continue, :start_capture}}
  end

  @impl true
  def handle_continue(:start_capture, state) do
    result =
      case state.helper_module.start_session_capture(self(), state.session_id, state.microphone_id) do
        :ok ->
          Watson.EventBus.publish(%Events.SessionStarted{
            session_id: state.session_id,
            session_dir: state.paths.session_dir,
            started_at: state.started_at
          })

          {:ok, %{active?: true, session_id: state.session_id, session_dir: state.paths.session_dir}}

        {:error, reason} ->
          {:error, reason}
      end

    Enum.each(state.start_waiters, &GenServer.reply(&1, result))
    {:noreply, %{state | start_result: result, start_waiters: []}}
  end

  @impl true
  def handle_call(:await_started, from, %{start_result: nil} = state) do
    {:noreply, %{state | start_waiters: state.start_waiters ++ [from]}}
  end

  def handle_call(:await_started, _from, state) do
    {:reply, state.start_result, state}
  end

  def handle_call(:stop, _from, state) do
    reply =
      with :ok <- state.helper_module.stop_session_capture(state.session_id),
           {:ok, mic_info} <- WavWriter.finalize(state.mic_writer),
           {:ok, system_info} <- WavWriter.finalize(state.system_writer),
           :ok <- finalize_transcripts(state, mic_info, system_info) do
        Watson.EventBus.publish(%Events.SessionStopped{
          session_id: state.session_id,
          session_dir: state.paths.session_dir,
          stopped_at: DateTime.utc_now()
        })

        :ok
      end

    {:stop, :normal, reply, state}
  end

  @impl true
  def handle_info({:audio_chunk, stream, timestamp_us, pcm}, state) do
    {writer, worker} = stream_targets(state, stream)
    :ok = WavWriter.append(writer, pcm)
    StreamWorker.notify_appended(worker, timestamp_us)

    Watson.EventBus.publish(%Events.AudioChunkReceived{
      session_id: state.session_id,
      stream: stream,
      timestamp_us: timestamp_us,
      bytes: byte_size(pcm)
    })

    {:noreply, state}
  end

  def handle_info({:helper_error, reason}, state) do
    Watson.EventBus.publish(%Events.HelperError{reason: reason, session_id: state.session_id})
    {:stop, {:helper_error, reason}, state}
  end

  defp stream_targets(state, :mic), do: {state.mic_writer, state.mic_worker}
  defp stream_targets(state, :system), do: {state.system_writer, state.system_worker}

  defp finalize_transcripts(state, mic_info, system_info) do
    with :ok <- maybe_transcribe_stream(state, :mic, mic_info),
         :ok <- maybe_transcribe_stream(state, :system, system_info),
         :ok <- postprocess_final(state, mic_info, system_info) do
      :ok
    end
  end

  defp maybe_transcribe_stream(_state, _stream, %{data_size: 0}), do: :ok

  defp maybe_transcribe_stream(state, :mic, _info) do
    with {:ok, result} <-
           MlxWhisper.transcribe(
             audio_path: state.paths.mic_wav,
             output_dir: state.paths.session_dir,
             output_name: "mic_transcript",
             model: state.model,
             language: state.language
           ) do
      Watson.EventBus.publish(%Events.FinalTranscript{
        session_id: state.session_id,
        stream: :mic,
        text_path: result.txt_path,
        tsv_path: result.tsv_path
      })

      :ok
    end
  end

  defp maybe_transcribe_stream(state, :system, _info) do
    with {:ok, result} <-
           MlxWhisper.transcribe(
             audio_path: state.paths.system_wav,
             output_dir: state.paths.session_dir,
             output_name: "system_transcript",
             model: state.model,
             language: state.language
           ) do
      Watson.EventBus.publish(%Events.FinalTranscript{
        session_id: state.session_id,
        stream: :system,
        text_path: result.txt_path,
        tsv_path: result.tsv_path
      })

      :ok
    end
  end

  defp postprocess_final(state, mic_info, system_info) do
    inputs =
      []
      |> maybe_add_input(mic_info.data_size > 0, %TranscriptInput{
        source: "MIC",
        tsv_path: state.paths.mic_transcript_tsv,
        cleaned_txt_path: state.paths.mic_cleaned_txt,
        cleaned_tsv_path: state.paths.mic_cleaned_tsv
      })
      |> maybe_add_input(system_info.data_size > 0, %TranscriptInput{
        source: "SYSTEM",
        tsv_path: state.paths.system_transcript_tsv,
        cleaned_txt_path: state.paths.system_cleaned_txt,
        cleaned_tsv_path: state.paths.system_cleaned_tsv
      })

    if inputs == [] do
      :ok
    else
      with {:ok, _result} <-
             Postprocessor.postprocess_transcripts(inputs, state.paths.dialogue_txt, state.paths.dialogue_tsv) do
        Watson.EventBus.publish(%Events.FinalTranscript{
          session_id: state.session_id,
          stream: :dialogue,
          text_path: state.paths.dialogue_txt,
          tsv_path: state.paths.dialogue_tsv
        })

        :ok
      end
    end
  end

  defp maybe_add_input(inputs, true, input), do: inputs ++ [input]
  defp maybe_add_input(inputs, false, _input), do: inputs
end
