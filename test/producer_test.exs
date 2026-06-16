defmodule ProducerTest do
  use ExUnit.Case, async: true

  setup {Req.Test, :set_req_test_to_shared}

  defmodule Forwarder do
    use Broadway

    def handle_message(_, message, %{test_pid: test_pid}) do
      send(test_pid, {:message_handled, message.data, self()})

      receive do
        :go -> message
      end
    end
  end

  test "gets updated until demand is met" do
    pid = start_broadway()
    test_pid = self()
    Req.Test.allow(MockClient, test_pid, pid)

    Req.Test.expect(MockClient, 3, fn
      %{body_params: %{"offset" => 0, "limit" => 3}} = conn ->
        send(test_pid, :first)

        response = %{
          "ok" => true,
          "result" => [
            %{"update_id" => 1},
            %{"update_id" => 2}
          ]
        }

        Req.Test.json(conn, response)

      %{body_params: %{"offset" => 3, "limit" => 1}} = conn ->
        send(test_pid, :second)

        response = %{
          "ok" => true,
          "result" => [
            %{"update_id" => 3}
          ]
        }

        Req.Test.json(conn, response)

      %{body_params: %{"offset" => 4} = params} ->
        send(test_pid, {:third, params})
        Process.sleep(:infinity)
    end)

    assert_receive :first
    assert_receive :second

    assert_receive {:message_handled, %{"update_id" => 2}, processor_pid}
    send(processor_pid, :go)
    assert_receive {:message_handled, %{"update_id" => 1}, _}
    send(processor_pid, :go)

    assert_receive {:third, %{"limit" => 2}}
    assert_receive {:message_handled, %{"update_id" => 3}, _}
  end

  defp start_broadway() do
    start_link_supervised!(%{
      id: __MODULE__,
      start:
        {Broadway, :start_link,
         [
           Forwarder,
           [
             name: __MODULE__,
             context: %{test_pid: self()},
             producer: [
               module:
                 {OffBroadway.Telegram.Producer,
                  token: "fake_token", plug: {Req.Test, MockClient}},
               concurrency: 1
             ],
             processors: [
               default: [concurrency: 1, max_demand: 3]
             ],
             shutdown: 10
           ]
         ]},
      type: :worker,
      restart: :permanent
    })
  end
end
