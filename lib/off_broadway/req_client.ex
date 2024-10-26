if Code.ensure_loaded?(Req) do
  defmodule OffBroadway.Telegram.ReqClient do
    @moduledoc """
    TelegramClient implementation using simple `Req`
    """
    require Logger

    alias OffBroadway.Telegram.TelegramClient

    @behaviour Broadway.Acknowledger
    @behaviour TelegramClient

    @url "https://api.telegram.org/bot:token/getUpdates"
    @default_timeout 60

    @impl TelegramClient
    def get_updates(offset, limit, opts) do
      token = Keyword.fetch!(opts, :token)

      params =
        opts
        |> Keyword.get(:params, %{})
        |> Map.merge(%{
          offset: offset,
          limit: limit,
          timeout: @default_timeout
        })

      Req.new(
        url: @url,
        json: params,
        path_params: [token: token],
        retry: false,
        receive_timeout: :timer.seconds(params[:timeout])
      )
      |> Req.post()
      |> case do
        {:ok, %{status: 200, body: %{"ok" => true, "result" => messages}}} ->
          {last_update_id, broadway_messages} = process_messages(messages)

          {last_update_id + 1, broadway_messages}

        error ->
          Logger.error("Unexpected response: #{inspect(error)}")

          {offset, []}
      end
    end

    defp process_messages([]), do: {0, []}
    defp process_messages(messages), do: process_messages(0, [], messages)

    defp process_messages(last_update_id, processed_messages, []),
      do: {last_update_id, processed_messages}

    defp process_messages(_, processed_messages, [%{"update_id" => update_id} = update | rest]) do
      process_messages(update_id, [to_broadway_message(update) | processed_messages], rest)
    end

    def to_broadway_message(%{} = update) do
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
