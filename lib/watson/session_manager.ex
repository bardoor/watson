defmodule Watson.SessionManager do
  @moduledoc false

  use GenServer

  alias Watson.Events
  alias Watson.Session

  defstruct [:session_pid, :session_ref, :session_id, :session_dir]

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec list_microphones() :: {:ok, [Watson.Capture.Device.t()]} | {:error, term()}
  def list_microphones do
    GenServer.call(__MODULE__, :list_microphones, 15_000)
  end

  @spec start_session(map()) :: {:ok, Session.status()} | {:error, term()}
  def start_session(opts) do
    GenServer.call(__MODULE__, {:start_session, opts}, :infinity)
  end

  @spec stop_session() :: :ok | {:error, term()}
  def stop_session do
    GenServer.call(__MODULE__, :stop_session, :infinity)
  end

  @spec session_status() :: Session.status()
  def session_status do
    GenServer.call(__MODULE__, :session_status)
  end

  @impl true
  def init(_opts) do
    {:ok, %__MODULE__{}}
  end

  @impl true
  def handle_call(:list_microphones, _from, state) do
    helper_module = Application.fetch_env!(:watson, :capture_helper)

    case helper_module.list_microphones() do
      {:ok, devices} = ok ->
        Watson.EventBus.publish(%Events.DevicesListed{devices: devices})
        {:reply, ok, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:start_session, _opts}, _from, %__MODULE__{session_pid: pid} = state) when is_pid(pid) do
    {:reply, {:error, :session_already_active}, state}
  end

  def handle_call({:start_session, opts}, _from, %__MODULE__{} = state) do
    helper_module = Application.fetch_env!(:watson, :capture_helper)

    session_opts = [
      recordings_dir: Application.fetch_env!(:watson, :recordings_dir),
      language: Map.get(opts, :language, Application.fetch_env!(:watson, :language)),
      model: Map.get(opts, :model, Application.fetch_env!(:watson, :model)),
      microphone_id: Map.get(opts, :microphone_id),
      helper_module: helper_module
    ]

    with {:ok, pid} <- Session.start_link(session_opts),
         {:ok, session_status} <- Session.await_started(pid) do
      ref = Process.monitor(pid)
      {:reply, {:ok, session_status}, %__MODULE__{state | session_pid: pid, session_ref: ref, session_id: session_status.session_id, session_dir: session_status.session_dir}}
    else
      {:error, _reason} = error ->
        {:reply, error, state}
    end
  end

  def handle_call(:stop_session, _from, %__MODULE__{session_pid: nil} = state) do
    {:reply, {:error, :no_active_session}, state}
  end

  def handle_call(:stop_session, _from, state) do
    reply = Session.stop(state.session_pid)
    {:reply, reply, state}
  end

  def handle_call(:session_status, _from, %__MODULE__{session_id: nil} = state) do
    {:reply, %{active?: false, session_id: nil, session_dir: nil}, state}
  end

  def handle_call(:session_status, _from, state) do
    {:reply, %{active?: true, session_id: state.session_id, session_dir: state.session_dir}, state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, pid, _reason}, %__MODULE__{session_ref: ref, session_pid: pid} = state) do
    {:noreply, %__MODULE__{state | session_pid: nil, session_ref: nil, session_id: nil, session_dir: nil}}
  end
end
