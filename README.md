# OffBroadway.Telegram

An Off-[Broadway](https://github.com/dashbitco/broadway) producer for [Telegram Bot API long polling](https://core.telegram.org/bots)

This package provides:

  * `OffBroadway.Telegram.Producer` - Broadway producer that polls updates from Telegram `getUpdates` long polling endpoint and feeds them through Broadway pipeline
  * `OffBroadway.Telegram.TelegramClient` - A generic behaviour to implement Telegram client
  * `OffBroadway.Telegram.ReqClient` - Telegram client based on `Req` package

## Why

Telegram bots have two ways of getting updates: long polling or web hook. While setting up a web hook is preferable way for production it is very common to use long polling in development environment or for smaller bots. Setting up a worker for long polling is not hard but consists mostly of [boilerplate code](https://github.com/lubien/elixir-telegram-bot-boilerplate/blob/master/lib/app/poller.ex).

But hey, we can use Broadway for this!

## Installation

Add `off_broadway_telegram` and `Req` to your list of dependencies in `mix.exs` :

```elixir
def deps do
  [
    {:off_broadway_telegram, "~> 0.1.0"},
    {:req, "~> 0.5.7"}
  ]
end
```

## Example

All you need to do is define a pipeline like this:

```elixir
defmodule BroadwayTelegramExample do
  use Broadway

  def start_link(bot_token) do
    Broadway.start_link(__MODULE__,
      name: __MODULE__,
      producer: [
        module:
          {OffBroadway.Telegram.Producer,
           [client: {OffBroadway.Telegram.ReqClient, [token: bot_token]}]},
        concurrency: 1
      ],
      processors: [
        default: [concurrency: 2]
      ]
    )
  end

  @impl Broadway
  def handle_message(
        _processor,
        %Broadway.Message{
          data: update
        } = message,
        _context
      ) do
    MyApp.process_update(update)

    message
  end
end
```

and add it to your application's supervisor tree in `application.ex`:

```
children = [
  {BroadwayTelegramExample, [Application.fetch_env!(:myapp, :bot_token)]]}
]

Supervisor.start_link(children, strategy: :one_for_one)
```

Everything else is up to your creativity!

## Caveats

Worth noting that **Telegram `getUpdates` is not a proper pubsub** like Google PubSub or SQS! This means:

  1. you don't want to run more than one producer process per bot
  2. there is no ack/nack and therefore no built-in retry mechanism
