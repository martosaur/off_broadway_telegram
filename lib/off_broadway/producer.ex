defmodule OffBroadway.Telegram.Producer do
  @moduledoc """
  A GenStage producer that continuously polls messages from a Telegram Bot API `getUpdates` endpoint

  ## Options

  The following options are supported:

    * `token` - required. Telegram bot token
    * `params` - optional. A map that will be merged into [`getUpdates`](https://core.telegram.org/bots/api#getupdates) request body

  """
  use GenStage

  @behaviour Broadway.Producer

  alias OffBroadway.Telegram.ReqClient

  @impl GenStage
  def init(opts) do
    {:producer,
     %{
       demand: 0,
       offset: 0,
       opts: Keyword.drop(opts, [:broadway])
     }}
  end

  @impl GenStage
  def handle_demand(incoming_demand, %{demand: demand} = state) do
    poll(%{state | demand: demand + incoming_demand})
  end

  @impl GenStage
  def handle_info(:receive_messages, state) do
    poll(state)
  end

  defp poll(%{demand: 0} = state) do
    {:noreply, [], state}
  end

  defp poll(%{demand: demand, offset: offset, opts: opts} = state) do
    {new_offset, messages} = ReqClient.get_updates(offset, demand, opts)
    new_demand = demand - length(messages)

    if new_demand > 0, do: schedule_receive_interval(0)

    {:noreply, messages, %{state | demand: new_demand, offset: new_offset}}
  end

  defp poll(state) do
    {:noreply, [], state}
  end

  defp schedule_receive_interval(interval) do
    Process.send_after(self(), :receive_messages, interval)
  end
end
