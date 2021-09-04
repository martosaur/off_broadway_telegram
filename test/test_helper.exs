defmodule Echo do
  use Broadway
  require Logger

  def start_link(_) do
    Broadway.start_link(__MODULE__,
      name: __MODULE__,
      producer: [
        module: {OffBroadway.Telegram.Producer, []},
        concurrency: 1
      ],
      processors: [
        default: [concurrency: 2]
      ]
    )
  end

  @impl Broadway
  def handle_message(_, message, _) do
    Logger.debug("Received message #{inspect(message)}")

    message
  end
end

ExUnit.start()
