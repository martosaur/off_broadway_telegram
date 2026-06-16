defmodule OffBroadway.Telegram.ReqClient do
  @moduledoc """
  Req-backed client used by `OffBroadway.Telegram.Producer` to poll Telegram updates.
  """
  require Logger

  @behaviour Broadway.Acknowledger

  @url "https://api.telegram.org/bot:token/getUpdates"
  @default_timeout 60

  def get_updates(offset, limit, opts) do
    {token, opts} = Keyword.pop!(opts, :token)
    {params, opts} = Keyword.pop(opts, :params, %{})

    params =
      %{timeout: @default_timeout}
      |> Map.merge(params)
      |> Map.merge(%{offset: offset, limit: limit})

    Req.new(
      url: @url,
      json: params,
      path_params: [token: token],
      receive_timeout: :timer.seconds(params[:timeout] + 1)
    )
    |> Req.merge(opts)
    |> Req.post()
    |> case do
      {:ok, %{status: 200, body: %{"ok" => true, "result" => []}}} ->
        {offset, []}

      {:ok, %{status: 200, body: %{"ok" => true, "result" => messages}}} ->
        {last_update_id, broadway_messages} = process_messages(messages)

        {last_update_id + 1, broadway_messages}

      error ->
        Logger.error(
          %{
            log_id: {OffBroadway.Telegram, :polling_updates_failed},
            error: error
          },
          error: error,
          report_cb: fn %{error: error} ->
            {"Error while polling Telegram updates: ~tw", [error]}
          end
        )

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
