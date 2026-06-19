defmodule Watson.Transcription.MlxWhisper do
  @moduledoc false

  defmodule Error do
    defexception [:message]
  end

  @spec transcribe(keyword()) :: {:ok, %{txt_path: String.t(), tsv_path: String.t()}} | {:error, term()}
  def transcribe(opts) do
    audio_path = Keyword.fetch!(opts, :audio_path)
    output_dir = Keyword.fetch!(opts, :output_dir)
    output_name = Keyword.fetch!(opts, :output_name)
    model = Keyword.fetch!(opts, :model)
    language = Keyword.fetch!(opts, :language)
    executable = Application.fetch_env!(:watson, :mlx_whisper_path)

    args = [
      audio_path,
      "--model",
      model,
      "--language",
      language,
      "--output-dir",
      output_dir,
      "--output-name",
      output_name,
      "-f",
      "all"
    ]

    try do
      case System.cmd(executable, args, stderr_to_stdout: true) do
        {_output, 0} ->
          txt_path = Path.join(output_dir, output_name <> ".txt")
          tsv_path = Path.join(output_dir, output_name <> ".tsv")

          if File.exists?(txt_path) and File.exists?(tsv_path) do
            {:ok, %{txt_path: txt_path, tsv_path: tsv_path}}
          else
            {:error, Error.exception(message: "mlx_whisper finished without expected outputs")}
          end

        {output, status} ->
          {:error, Error.exception(message: "mlx_whisper failed with status #{status}: #{String.trim(output)}")}
      end
    rescue
      error in ErlangError ->
        {:error, Error.exception(message: "mlx_whisper execution failed: #{Exception.message(error)}")}
    end
  end
end
