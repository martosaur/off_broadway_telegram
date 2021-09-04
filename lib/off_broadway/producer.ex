defmodule OffBroadway.Telegram.Producer do
  @moduledoc """
  A GenStage producer that continuously polls messages from a Telegram Bot API `getUpdates` endpoint

  ## Options

  The following options are supported:

    * `receive_interval` - for how long (in milliseconds) a producer will wait before checking for updates.
    * `client` - a module-options tuple that implements `OffBroadway.Telegram.TelegramClient` behaviour. Default: `{OffBroadway.Telegram.NadiaClient, []}`

  """
  use GenStage

  @behaviour Broadway.Producer

  @default_client {OffBroadway.Telegram.NadiaClient, []}
  @default_receive_interval 1_000

  @impl GenStage
  def init(opts) do
    {client, client_opts} = Keyword.get(opts, :client, @default_client)
    receive_interval = Keyword.get(opts, :receive_interval, @default_receive_interval)

    {:producer,
     %{
       demand: 0,
       offset: 0,
       receive_interval: receive_interval,
       receive_timer: nil,
       client: client,
       client_opts: client_opts
     }}
  end

  @impl GenStage
  def handle_demand(incoming_demand, %{demand: demand} = state) do
    handle_receive_messages(%{state | demand: demand + incoming_demand})
  end

  @impl GenStage
  def handle_info(:receive_messages, %{receive_timer: nil} = state) do
    {:noreply, [], state}
  end

  @impl GenStage
  def handle_info(:receive_messages, state) do
    handle_receive_messages(%{state | receive_timer: nil})
  end

  defp handle_receive_messages(
         %{demand: demand, offset: offset, client: client, client_opts: opts} = state
       ) do
    {new_offset, messages} = apply(client, :get_updates, [offset, demand, opts])
    new_demand = demand - length(messages)

    receive_timer =
      case {messages, new_demand} do
        {[], _} -> schedule_receive_interval(state.receive_interval)
        {_, 0} -> nil
        _ -> schedule_receive_interval(0)
      end

    {:noreply, messages,
     %{state | demand: new_demand, offset: new_offset, receive_timer: receive_timer}}
  end

  defp handle_receive_messages(state) do
    {:noreply, [], state}
  end

  defp schedule_receive_interval(interval) do
    Process.send_after(self(), :receive_messages, interval)
  end
end
