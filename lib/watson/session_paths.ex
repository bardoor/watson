defmodule Watson.SessionPaths do
  @moduledoc false

  @enforce_keys [:session_dir]
  defstruct [
    :session_dir,
    :mic_wav,
    :system_wav,
    :mic_partial_txt,
    :system_partial_txt,
    :mic_transcript_txt,
    :system_transcript_txt,
    :mic_transcript_tsv,
    :system_transcript_tsv,
    :mic_cleaned_txt,
    :mic_cleaned_tsv,
    :system_cleaned_txt,
    :system_cleaned_tsv,
    :dialogue_txt,
    :dialogue_tsv
  ]

  @type t() :: %__MODULE__{
          session_dir: String.t(),
          mic_wav: String.t(),
          system_wav: String.t(),
          mic_partial_txt: String.t(),
          system_partial_txt: String.t(),
          mic_transcript_txt: String.t(),
          system_transcript_txt: String.t(),
          mic_transcript_tsv: String.t(),
          system_transcript_tsv: String.t(),
          mic_cleaned_txt: String.t(),
          mic_cleaned_tsv: String.t(),
          system_cleaned_txt: String.t(),
          system_cleaned_tsv: String.t(),
          dialogue_txt: String.t(),
          dialogue_tsv: String.t()
        }

  @spec create!(String.t()) :: t()
  def create!(root_dir) do
    session_id = Calendar.strftime(DateTime.utc_now(), "%Y-%m-%d_%H-%M-%S")
    session_dir = Path.join(root_dir, session_id)
    File.mkdir_p!(session_dir)

    %__MODULE__{
      session_dir: session_dir,
      mic_wav: Path.join(session_dir, "mic.wav"),
      system_wav: Path.join(session_dir, "system.wav"),
      mic_partial_txt: Path.join(session_dir, "mic_transcript.partial.txt"),
      system_partial_txt: Path.join(session_dir, "system_transcript.partial.txt"),
      mic_transcript_txt: Path.join(session_dir, "mic_transcript.txt"),
      system_transcript_txt: Path.join(session_dir, "system_transcript.txt"),
      mic_transcript_tsv: Path.join(session_dir, "mic_transcript.tsv"),
      system_transcript_tsv: Path.join(session_dir, "system_transcript.tsv"),
      mic_cleaned_txt: Path.join(session_dir, "mic_transcript.cleaned.txt"),
      mic_cleaned_tsv: Path.join(session_dir, "mic_transcript.cleaned.tsv"),
      system_cleaned_txt: Path.join(session_dir, "system_transcript.cleaned.txt"),
      system_cleaned_tsv: Path.join(session_dir, "system_transcript.cleaned.tsv"),
      dialogue_txt: Path.join(session_dir, "dialogue_transcript.txt"),
      dialogue_tsv: Path.join(session_dir, "dialogue_transcript.tsv")
    }
  end
end
