defmodule Watson.Application do
  use Application

  @impl true
  def start(_type, _args) do
    helper_module = Application.fetch_env!(:watson, :capture_helper)

    children = [
      {Registry, keys: :duplicate, name: Watson.EventRegistry},
      helper_module,
      Watson.SessionManager
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Watson.Supervisor)
  end
end
