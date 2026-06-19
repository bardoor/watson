defmodule Watson do
  @moduledoc false

  alias Watson.SessionManager

  @spec list_microphones() :: {:ok, [Watson.Capture.Device.t()]} | {:error, term()}
  def list_microphones do
    SessionManager.list_microphones()
  end

  @spec subscribe() :: :ok
  def subscribe do
    Watson.EventBus.subscribe()
  end

  @spec start_session(map()) :: {:ok, Watson.Session.status()} | {:error, term()}
  def start_session(opts \\ %{}) do
    SessionManager.start_session(opts)
  end

  @spec stop_session() :: :ok | {:error, term()}
  def stop_session do
    SessionManager.stop_session()
  end

  @spec session_status() :: Watson.Session.status()
  def session_status do
    SessionManager.session_status()
  end
end
