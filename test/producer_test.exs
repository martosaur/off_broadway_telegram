defmodule OffBroadway.Telegram.ProducerTest do
  use ExUnit.Case

  defmodule MessageServer do
    def start_link() do
      Agent.start_link(fn -> [] end)
    end

    def push_messages(server, messages) do
      Agent.update(server, fn queue -> queue ++ messages end)
    end

    def take_messages(server, amount) do
      Agent.get_and_update(server, fn queue -> Enum.split(queue, amount) end)
    end
  end

  defmodule FakeTelegramClient do
    @behaviour OffBroadway.Telegram.TelegramClient
    @behaviour Broadway.Acknowledger

    @impl true
    def get_updates(offset, limit, opts) do
      messages = MessageServer.take_messages(opts[:message_server], limit)
      send(opts[:test_pid], {:messages_received, length(messages), offset})

      {messages, offset} =
        Enum.map_reduce(messages, offset, fn message, _acc ->
          broadway_message = %Broadway.Message{
            data: message,
            metadata: %{},
            acknowledger: {__MODULE__, :ack_ref, :ack_data}
          }

          {broadway_message, message}
        end)

      {offset, messages}
    end

    @impl true
    def ack(_ack_ref, _successful, _failed), do: :ok
  end

  defmodule Forwarder do
    use Broadway

    def handle_message(_, message, %{test_pid: test_pid}) do
      send(test_pid, {:message_handled, message.data})
      message
    end
  end

  test "receive messages when the queue has less than the demand" do
    {:ok, message_server} = MessageServer.start_link()
    MessageServer.push_messages(message_server, 1..20)

    {:ok, pid} = start_broadway(message_server)

    assert_receive {:messages_received, 10, 0}

    for msg <- 1..10 do
      assert_receive {:message_handled, ^msg}
    end

    stop_broadway(pid)
  end

  test "keep receiving messages when the queue has more than the demand" do
    {:ok, message_server} = MessageServer.start_link()
    MessageServer.push_messages(message_server, 1..20)

    {:ok, pid} = start_broadway(message_server)

    assert_receive {:messages_received, 10, 0}

    for msg <- 1..10 do
      assert_receive {:message_handled, ^msg}
    end

    assert_receive {:messages_received, 5, 10}

    for msg <- 11..15 do
      assert_receive {:message_handled, ^msg}
    end

    assert_receive {:messages_received, 5, 15}

    for msg <- 16..20 do
      assert_receive {:message_handled, ^msg}
    end

    stop_broadway(pid)
  end

  test "keep trying to receive new messages when the queue is empty" do
    {:ok, message_server} = MessageServer.start_link()
    {:ok, pid} = start_broadway(message_server)

    MessageServer.push_messages(message_server, [13, 14])

    assert_receive {:messages_received, 2, 0}
    assert_receive {:message_handled, 13}
    assert_receive {:message_handled, 14}

    assert_receive {:messages_received, 0, 14}
    refute_receive {:messages_handled, _, _}

    MessageServer.push_messages(message_server, [15, 16])

    assert_receive {:messages_received, 2, 14}
    assert_receive {:message_handled, 15}
    assert_receive {:message_handled, 16}

    stop_broadway(pid)
  end

  defp start_broadway(broadway_name \\ new_unique_name(), message_server, opts \\ []) do
    Broadway.start_link(
      Forwarder,
      name: broadway_name,
      context: %{test_pid: self()},
      producer: [
        module:
          {OffBroadway.Telegram.Producer,
           Keyword.merge(
             [
               client: {FakeTelegramClient, [test_pid: self(), message_server: message_server]},
               receive_interval: 0
             ],
             opts
           )},
        concurrency: 1
      ],
      processors: [
        default: [concurrency: 1]
      ]
    )
  end

  defp new_unique_name() do
    :"Broadway#{System.unique_integer([:positive, :monotonic])}"
  end

  defp stop_broadway(pid) do
    ref = Process.monitor(pid)
    Process.exit(pid, :normal)

    receive do
      {:DOWN, ^ref, _, _, _} -> :ok
    end
  end
end
