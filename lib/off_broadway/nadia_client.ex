if Code.ensure_loaded?(Nadia) do
  defmodule OffBroadway.Telegram.NadiaClient do
    @moduledoc """
    TelegramClient implementation using `Nadia`
    """
    require Logger

    alias Nadia.Model.Update
    alias OffBroadway.Telegram.TelegramClient

    @behaviour Broadway.Acknowledger
    @behaviour TelegramClient

    @impl TelegramClient
    def get_updates(offset, limit, opts) do
      opts
      |> Keyword.merge(opts, offset: offset, limit: limit)
      |> Nadia.get_updates()
      |> case do
        {:ok, messages} ->
          {last_update_id, broadway_messages} = process_messages(messages)

          {last_update_id + 1, broadway_messages}

        error ->
          Logger.error("Error getting updates: #{inspect(error)}")

          {offset, []}
      end
    end

    defp process_messages([]), do: {0, []}
    defp process_messages(messages), do: process_messages(0, [], messages)

    defp process_messages(last_update_id, processed_messages, []),
      do: {last_update_id, processed_messages}

    defp process_messages(_, processed_messages, [%Update{update_id: update_id} = update | rest]) do
      process_messages(update_id, [to_broadway_message(update) | processed_messages], rest)
    end

    def to_broadway_message(%Update{} = update) do
      %Broadway.Message{
        data: update,
        metadata: %{},
        acknowledger: {__MODULE__, nil, nil}
      }
    end

    @impl Broadway.Acknowledger
    def ack(_ack_ref, _successful, _failed), do: :ok

    @impl Broadway.Acknowledger
    def configure(_ack_ref, ack_data, _options), do: {:ok, ack_data}
  end
end
