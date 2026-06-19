defmodule Watson.Transcription.Postprocessor do
  @moduledoc false

  defmodule TranscriptInput do
    @enforce_keys [:source, :tsv_path, :cleaned_txt_path, :cleaned_tsv_path]
    defstruct [:source, :tsv_path, :cleaned_txt_path, :cleaned_tsv_path]

    @type t() :: %__MODULE__{
            source: String.t(),
            tsv_path: String.t(),
            cleaned_txt_path: String.t(),
            cleaned_tsv_path: String.t()
          }
  end

  defmodule Segment do
    @enforce_keys [:source, :start_ms, :end_ms, :text]
    defstruct [:source, :start_ms, :end_ms, :text]

    @type t() :: %__MODULE__{
            source: String.t(),
            start_ms: non_neg_integer(),
            end_ms: non_neg_integer(),
            text: String.t()
          }
  end

  defmodule SourceStats do
    defstruct raw: 0, kept: 0, empty: 0, invalid_timing: 0, punctuation_only: 0, duplicate: 0, known_noise: 0

    @type t() :: %__MODULE__{
            raw: non_neg_integer(),
            kept: non_neg_integer(),
            empty: non_neg_integer(),
            invalid_timing: non_neg_integer(),
            punctuation_only: non_neg_integer(),
            duplicate: non_neg_integer(),
            known_noise: non_neg_integer()
          }
  end

  defmodule Result do
    @enforce_keys [:dialogue_txt_path, :dialogue_tsv_path, :stats, :turns]
    defstruct [:dialogue_txt_path, :dialogue_tsv_path, :stats, :turns]

    @type t() :: %__MODULE__{
            dialogue_txt_path: String.t(),
            dialogue_tsv_path: String.t(),
            stats: %{String.t() => SourceStats.t()},
            turns: non_neg_integer()
          }
  end

  @ascii_punctuation "!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~"
  @punctuation_chars String.graphemes(@ascii_punctuation <> "«»“”„…—–‑·•") |> MapSet.new()
  @noise_phrases MapSet.new(["субтитры сделал dimatorzok"])

  @spec postprocess_transcripts([TranscriptInput.t()], String.t(), String.t(), keyword()) ::
          {:ok, Result.t()} | {:error, term()}
  def postprocess_transcripts(inputs, dialogue_txt_path, dialogue_tsv_path, opts \\ []) do
    merge_gap_ms = Keyword.get(opts, :merge_gap_ms, 1_500)
    stats = Map.new(inputs, fn input -> {input.source, %SourceStats{}} end)

    with {:ok, raw_segments, stats} <- read_segments(inputs, stats) do
      cleaned_segments =
        raw_segments
        |> Enum.sort_by(fn segment -> {segment.start_ms, segment.end_ms, segment.source} end)
        |> clean_segments(stats)

      turns = merge_adjacent_segments(cleaned_segments.segments, merge_gap_ms)
      :ok = write_source_outputs(inputs, cleaned_segments.segments)
      :ok = write_dialogue_outputs(dialogue_txt_path, dialogue_tsv_path, turns)

      {:ok,
       %Result{
         dialogue_txt_path: dialogue_txt_path,
         dialogue_tsv_path: dialogue_tsv_path,
         stats: cleaned_segments.stats,
         turns: length(turns)
       }}
    end
  end

  defp read_segments(inputs, stats) do
    Enum.reduce_while(inputs, {:ok, [], stats}, fn input, {:ok, acc_segments, acc_stats} ->
      if File.exists?(input.tsv_path) do
        with {:ok, content} <- File.read(input.tsv_path) do
          {segments, source_stats} = parse_tsv(content, input.source, Map.fetch!(acc_stats, input.source))
          {:cont, {:ok, acc_segments ++ segments, Map.put(acc_stats, input.source, source_stats)}}
        else
          {:error, reason} -> {:halt, {:error, reason}}
        end
      else
        {:cont, {:ok, acc_segments, acc_stats}}
      end
    end)
  end

  defp parse_tsv(content, source, source_stats) do
    rows =
      content
      |> String.split("\n", trim: true)
      |> Enum.drop(1)

    Enum.reduce(rows, {[], source_stats}, fn row, {segments, stats} ->
      columns = String.split(row, "\t")
      stats = %{stats | raw: stats.raw + 1}

      case columns do
        [start_ms, end_ms, text] ->
          build_segment(source, start_ms, end_ms, text, segments, stats)

        [start_ms, end_ms, _source, text] ->
          build_segment(source, start_ms, end_ms, text, segments, stats)

        _ ->
          {segments, %{stats | invalid_timing: stats.invalid_timing + 1}}
      end
    end)
  end

  defp build_segment(source, start_ms, end_ms, text, segments, stats) do
    text = String.trim(text)

    cond do
      text == "" ->
        {segments, %{stats | empty: stats.empty + 1}}

      true ->
        case {Integer.parse(start_ms), Integer.parse(end_ms)} do
          {{start_ms, ""}, {end_ms, ""}} when start_ms < end_ms ->
            {
              segments ++ [%Segment{source: source, start_ms: start_ms, end_ms: end_ms, text: text}],
              stats
            }

          _ ->
            {segments, %{stats | invalid_timing: stats.invalid_timing + 1}}
        end
    end
  end

  defp clean_segments(segments, stats) do
    Enum.reduce(segments, %{segments: [], seen: MapSet.new(), stats: stats}, fn segment, acc ->
      source_stats = Map.fetch!(acc.stats, segment.source)
      normalized = normalize_text(segment.text)

      cond do
        known_noise?(normalized) ->
          put_in(acc.stats[segment.source], %{source_stats | known_noise: source_stats.known_noise + 1})

        punctuation_only?(segment.text) ->
          put_in(acc.stats[segment.source], %{source_stats | punctuation_only: source_stats.punctuation_only + 1})

        MapSet.member?(acc.seen, normalized) ->
          put_in(acc.stats[segment.source], %{source_stats | duplicate: source_stats.duplicate + 1})

        true ->
          %{
            acc
            | segments: acc.segments ++ [segment],
              seen: MapSet.put(acc.seen, normalized),
              stats: Map.put(acc.stats, segment.source, %{source_stats | kept: source_stats.kept + 1})
          }
      end
    end)
  end

  defp normalize_text(text) do
    text
    |> String.downcase()
    |> String.replace("ё", "е")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> String.trim(@ascii_punctuation <> "«»“”„…—–‑")
  end

  defp known_noise?(normalized_text), do: MapSet.member?(@noise_phrases, normalized_text)

  defp punctuation_only?(text) do
    compact = String.replace(text, ~r/\s+/, "")
    compact != "" and Enum.all?(String.graphemes(compact), &MapSet.member?(@punctuation_chars, &1))
  end

  defp merge_adjacent_segments(segments, merge_gap_ms) do
    Enum.reduce(segments, [], fn segment, turns ->
      case List.last(turns) do
        %Segment{} = previous
        when previous.source == segment.source and segment.start_ms - previous.end_ms <= merge_gap_ms ->
          List.replace_at(
            turns,
            -1,
            %Segment{
              source: previous.source,
              start_ms: previous.start_ms,
              end_ms: max(previous.end_ms, segment.end_ms),
              text: previous.text <> " " <> segment.text
            }
          )

        _ ->
          turns ++ [segment]
      end
    end)
  end

  defp write_source_outputs(inputs, segments) do
    Enum.each(inputs, fn input ->
      source_segments = Enum.filter(segments, &(&1.source == input.source))
      write_plain_text(input.cleaned_txt_path, source_segments, false)
      write_tsv(input.cleaned_tsv_path, source_segments, false)
    end)
  end

  defp write_dialogue_outputs(dialogue_txt_path, dialogue_tsv_path, turns) do
    write_plain_text(dialogue_txt_path, turns, true)
    write_tsv(dialogue_tsv_path, turns, true)
  end

  defp write_plain_text(path, segments, include_source) do
    lines =
      Enum.map_join(segments, "\n", fn segment ->
        prefix =
          if include_source do
            "#{format_ms(segment.start_ms)} [#{segment.source}]"
          else
            format_ms(segment.start_ms)
          end

        prefix <> " " <> segment.text
      end)

    File.write!(path, if(lines == "", do: "", else: lines <> "\n"))
  end

  defp write_tsv(path, segments, include_source) do
    header =
      if include_source do
        "start\tend\tsource\ttext\n"
      else
        "start\tend\ttext\n"
      end

    rows =
      Enum.map_join(segments, "", fn segment ->
        if include_source do
          "#{segment.start_ms}\t#{segment.end_ms}\t#{segment.source}\t#{segment.text}\n"
        else
          "#{segment.start_ms}\t#{segment.end_ms}\t#{segment.text}\n"
        end
      end)

    File.write!(path, header <> rows)
  end

  defp format_ms(ms) do
    total_seconds = div(ms, 1000)
    milliseconds = rem(ms, 1000)
    minutes = div(total_seconds, 60)
    seconds = rem(total_seconds, 60)
    hours = div(minutes, 60)
    minutes = rem(minutes, 60)

    if hours > 0 do
      :io_lib.format("~2..0B:~2..0B:~2..0B.~3..0B", [hours, minutes, seconds, milliseconds]) |> IO.iodata_to_binary()
    else
      :io_lib.format("~2..0B:~2..0B.~3..0B", [minutes, seconds, milliseconds]) |> IO.iodata_to_binary()
    end
  end
end
