defmodule Watson.Capture.Helper do
  @moduledoc false

  use GenServer

  alias Watson.Capture.Protocol
  alias Watson.Events

  defstruct [
    :port,
    :active_session_id,
    :active_session_pid,
    pending_devices: nil,
    pending_start: nil,
    pending_stop: nil
  ]

  @type t() :: %__MODULE__{
          port: port(),
          active_session_id: String.t() | nil,
          active_session_pid: pid() | nil,
          pending_devices: GenServer.from() | nil,
          pending_start: {GenServer.from(), pid(), String.t()} | nil,
          pending_stop: {GenServer.from(), String.t()} | nil
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec list_microphones() :: {:ok, [Watson.Capture.Device.t()]} | {:error, term()}
  def list_microphones do
    GenServer.call(__MODULE__, :list_microphones, 15_000)
  end

  @spec start_session_capture(pid(), String.t(), String.t() | nil) :: :ok | {:error, term()}
  def start_session_capture(session_pid, session_id, microphone_id) do
    GenServer.call(__MODULE__, {:start_session_capture, session_pid, session_id, microphone_id}, 30_000)
  end

  @spec stop_session_capture(String.t()) :: :ok | {:error, term()}
  def stop_session_capture(session_id) do
    GenServer.call(__MODULE__, {:stop_session_capture, session_id}, 30_000)
  end

  @impl true
  def init(_opts) do
    Process.flag(:trap_exit, true)

    with {:ok, executable_path} <- executable_path(),
         {:ok, port} <- open_port(executable_path) do
      {:ok, %__MODULE__{port: port}}
    else
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call(:list_microphones, from, %__MODULE__{pending_devices: nil} = state) do
    case Port.command(state.port, Protocol.encode_command(:list_devices)) do
      true -> {:noreply, %{state | pending_devices: from}}
      false -> {:reply, {:error, :port_command_failed}, state}
    end
  end

  def handle_call(:list_microphones, _from, state) do
    {:reply, {:error, :devices_request_in_flight}, state}
  end

  def handle_call({:start_session_capture, session_pid, session_id, microphone_id}, from, state) do
    cond do
      state.active_session_pid != nil ->
        {:reply, {:error, :session_already_active}, state}

      state.pending_start != nil ->
        {:reply, {:error, :session_start_in_flight}, state}

      true ->
        payload =
          %{session_id: session_id}
          |> maybe_put(:microphone_id, microphone_id)

        case Port.command(state.port, Protocol.encode_command(:start_session, payload)) do
          true ->
            {:noreply, %{state | pending_start: {from, session_pid, session_id}}}

          false ->
            {:reply, {:error, :port_command_failed}, state}
        end
    end
  end

  def handle_call({:stop_session_capture, session_id}, from, state) do
    cond do
      state.active_session_id != session_id ->
        {:reply, {:error, :session_not_active}, state}

      state.pending_stop != nil ->
        {:reply, {:error, :session_stop_in_flight}, state}

      true ->
        case Port.command(state.port, Protocol.encode_command(:stop_session, %{session_id: session_id})) do
          true -> {:noreply, %{state | pending_stop: {from, session_id}}}
          false -> {:reply, {:error, :port_command_failed}, state}
        end
    end
  end

  @impl true
  def handle_info({port, {:data, packet}}, %__MODULE__{port: port} = state) do
    case Protocol.decode_frame(packet) do
      {:ok, {:devices, devices}} ->
        state = reply_if_pending(state.pending_devices, {:ok, devices}, %{state | pending_devices: nil})
        {:noreply, state}

      {:ok, {:session_started, session_id}} ->
        {:noreply, handle_session_started(state, session_id)}

      {:ok, {:session_stopped, session_id}} ->
        {:noreply, handle_session_stopped(state, session_id)}

      {:ok, {:helper_error, reason}} ->
        {:noreply, handle_helper_error(state, reason)}

      {:ok, {:audio_chunk, stream, timestamp_us, pcm}} ->
        if state.active_session_pid, do: send(state.active_session_pid, {:audio_chunk, stream, timestamp_us, pcm})
        {:noreply, state}

      {:error, reason} ->
        {:noreply, handle_helper_error(state, "protocol decode failed: #{inspect(reason)}")}
    end
  end

  def handle_info({port, {:exit_status, status}}, %__MODULE__{port: port} = state) do
    {:stop, {:port_exit, status}, state}
  end

  def handle_info({:EXIT, port, reason}, %__MODULE__{port: port} = state) do
    {:stop, reason, state}
  end

  @impl true
  def terminate(reason, state) do
    notify_failure(state, "helper terminated: #{inspect(reason)}")
    :ok
  end

  defp executable_path do
    path = Application.fetch_env!(:watson, :helper_path)

    if File.exists?(path) do
      {:ok, path}
    else
      {:error, {:helper_not_found, path}}
    end
  end

  defp open_port(executable_path) do
    try do
      port =
        Port.open({:spawn_executable, executable_path}, [
          :binary,
          {:packet, 4},
          :use_stdio,
          :exit_status,
          :hide,
          :stderr_to_stdout
        ])

      {:ok, port}
    rescue
      error -> {:error, error}
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp reply_if_pending(nil, _reply, state), do: state

  defp reply_if_pending(from, reply, state) do
    GenServer.reply(from, reply)
    state
  end

  defp handle_session_started(%__MODULE__{pending_start: {from, session_pid, session_id}} = state, session_id) do
    GenServer.reply(from, :ok)
    %{state | pending_start: nil, active_session_pid: session_pid, active_session_id: session_id}
  end

  defp handle_session_started(state, _session_id) do
    handle_helper_error(state, "unexpected session_started event")
  end

  defp handle_session_stopped(%__MODULE__{pending_stop: {from, session_id}} = state, session_id) do
    GenServer.reply(from, :ok)
    %{state | pending_stop: nil, active_session_pid: nil, active_session_id: nil}
  end

  defp handle_session_stopped(state, _session_id) do
    handle_helper_error(state, "unexpected session_stopped event")
  end

  defp handle_helper_error(state, reason) do
    notify_failure(state, reason)

    if state.pending_devices, do: GenServer.reply(state.pending_devices, {:error, reason})

    if state.pending_start do
      {from, _session_pid, _session_id} = state.pending_start
      GenServer.reply(from, {:error, reason})
    end

    if state.pending_stop do
      {from, _session_id} = state.pending_stop
      GenServer.reply(from, {:error, reason})
    end

    %{
      state
      | pending_devices: nil,
        pending_start: nil,
        pending_stop: nil,
        active_session_pid: nil,
        active_session_id: nil
    }
  end

  defp notify_failure(state, reason) do
    Watson.EventBus.publish(%Events.HelperError{reason: reason, session_id: state.active_session_id})

    if state.active_session_pid do
      send(state.active_session_pid, {:helper_error, reason})
    end
  end
end
