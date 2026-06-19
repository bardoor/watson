defmodule Watson.EventBus do
  @moduledoc false

  @topic __MODULE__

  @spec subscribe() :: :ok
  def subscribe do
    Registry.register(Watson.EventRegistry, @topic, [])
    :ok
  end

  @spec publish(struct()) :: :ok
  def publish(event) do
    Registry.dispatch(Watson.EventRegistry, @topic, fn entries ->
      for {pid, _} <- entries, do: send(pid, {:watson_event, event})
    end)

    :ok
  end
end
