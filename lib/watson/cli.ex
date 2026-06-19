defmodule Watson.CLI do
  @moduledoc false

  @spec main([String.t()]) :: no_return()
  def main(args) do
    with {:ok, _apps} <- Application.ensure_all_started(:watson) do
      run(args)
    else
      {:error, reason} ->
        IO.puts(:stderr, "failed to start watson: #{inspect(reason)}")
        System.halt(1)
    end
  end

  defp run(["devices"]) do
    Watson.subscribe()

    case Watson.list_microphones() do
      {:ok, devices} ->
        Enum.each(devices, fn device ->
          marker = if device.is_default, do: " (default)", else: ""
          IO.puts("#{device.id}\t#{device.name}#{marker}")
        end)

        System.halt(0)

      {:error, reason} ->
        IO.puts(:stderr, "failed to list devices: #{inspect(reason)}")
        System.halt(1)
    end
  end

  defp run(["record" | rest]) do
    Watson.subscribe()

    {opts, _argv, _invalid} =
      OptionParser.parse(rest,
        strict: [language: :string, model: :string, microphone_id: :string]
      )

    session_opts =
      opts
      |> Enum.into(%{})
      |> normalize_keys()

    case Watson.start_session(session_opts) do
      {:ok, _status} ->
        IO.puts("Recording started.")
        IO.puts("Press Enter to stop.")
        start_stop_watcher()
        event_loop()

      {:error, reason} ->
        IO.puts(:stderr, "failed to start session: #{inspect(reason)}")
        System.halt(1)
    end
  end

  defp run(_args) do
    IO.puts("""
    usage:
      watson devices
      watson record [--language ru] [--model MODEL] [--microphone-id ID]
    """)

    System.halt(1)
  end

  defp normalize_keys(opts) do
    Enum.reduce(opts, %{}, fn
      {:microphone_id, value}, acc -> Map.put(acc, :microphone_id, value)
      {:language, value}, acc -> Map.put(acc, :language, value)
      {:model, value}, acc -> Map.put(acc, :model, value)
    end)
  end

  defp start_stop_watcher do
    parent = self()

    spawn_link(fn ->
      _ = IO.gets("")
      send(parent, :stop_requested_from_stdin)
    end)
  end

  defp event_loop do
    receive do
      :stop_requested_from_stdin ->
        _ = Watson.stop_session()
        event_loop()

      {:watson_event, %Watson.Events.PartialTranscript{stream: stream, text: text}} ->
        IO.puts("[partial #{stream}] #{text}")
        event_loop()

      {:watson_event, %Watson.Events.FinalTranscript{stream: stream, text_path: text_path}} ->
        IO.puts("[final #{stream}] #{text_path}")
        event_loop()

      {:watson_event, %Watson.Events.HelperError{reason: reason}} ->
        IO.puts(:stderr, "helper error: #{reason}")
        event_loop()

      {:watson_event, %Watson.Events.SessionStopped{session_dir: session_dir}} ->
        IO.puts("Session finalized: #{session_dir}")
        System.halt(0)

      {:watson_event, _event} ->
        event_loop()
    end
  end
end
