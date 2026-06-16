defmodule OffBroadway.Telegram.Producer do
  @moduledoc """
  A GenStage producer that continuously polls messages from a Telegram Bot API `getUpdates` endpoint

  ## Options

  The following options are supported:

    * `token` - required. Telegram bot token
    * `task_supervisor` - required. Task supervisor used for polling requests
    * `params` - optional. A map that will be merged into [`getUpdates`](https://core.telegram.org/bots/api#getupdates) request body

  """
  use GenStage

  @behaviour Broadway.Producer

  alias OffBroadway.Telegram.ReqClient

  defstruct [
    :task_supervisor,
    :opts,
    :task,
    demand: 0,
    offset: 0
  ]

  @impl GenStage
  def init(opts) do
    state = %__MODULE__{
      task_supervisor: Keyword.fetch!(opts, :task_supervisor),
      opts: Keyword.drop(opts, [:broadway, :task_supervisor])
    }

    {:producer, state}
  end

  @impl GenStage
  def handle_demand(incoming_demand, state) do
    poll(%{state | demand: state.demand + incoming_demand})
  end

  @impl GenStage
  def handle_info(:receive_messages, state) do
    poll(state)
  end

  def handle_info({ref, {new_offset, messages}}, %__MODULE__{task: %Task{ref: ref}} = state) do
    new_demand = state.demand - length(messages)

    if new_demand > 0, do: schedule_receive_interval(0)

    {:noreply, messages, %{state | demand: new_demand, offset: new_offset, task: nil}}
  end

  def handle_info({:DOWN, _ref, :process, _, :normal}, state) do
    {:noreply, [], state}
  end

  def handle_info({:DOWN, ref, :process, _, _reason}, %{task: %Task{ref: ref}} = state) do
    schedule_receive_interval(0)
    {:noreply, [], %{state | task: nil}}
  end

  @impl Broadway.Producer
  def prepare_for_draining(%{task: nil} = state) do
    {:noreply, [], state}
  end

  @impl true
  def prepare_for_draining(state) do
    Task.shutdown(state.task, :brutal_kill)

    {:noreply, [], %{state | task: nil}}
  end

  defp poll(%__MODULE__{demand: 0} = state) do
    {:noreply, [], state}
  end

  defp poll(%__MODULE__{task: nil} = state) do
    task =
      Task.Supervisor.async_nolink(
        state.task_supervisor,
        ReqClient,
        :get_updates,
        [
          state.offset,
          state.demand,
          state.opts
        ],
        shutdown: :brutal_kill
      )

    {:noreply, [], %{state | task: task}}
  end

  defp poll(state) do
    {:noreply, [], state}
  end

  defp schedule_receive_interval(interval) do
    Process.send_after(self(), :receive_messages, interval)
  end
end
