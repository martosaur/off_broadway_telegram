defmodule ProducerTest do
  use ExUnit.Case

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

  setup_all do
    start_link_supervised!({Task.Supervisor, name: __MODULE__.Supervisor})
    :ok
  end

  test "gets updated until demand is met" do
    test_pid = self()

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

    start_broadway()

    assert_receive :first
    assert_receive :second

    assert_receive {:message_handled, %{"update_id" => 2}, processor_pid}
    send(processor_pid, :go)
    assert_receive {:message_handled, %{"update_id" => 1}, _}
    send(processor_pid, :go)

    assert_receive {:third, %{"limit" => 2}}
    assert_receive {:message_handled, %{"update_id" => 3}, _}
  end

  @tag capture_log: true
  test "task crashes" do
    test_pid = self()

    Req.Test.expect(MockClient, 3, fn
      %{body_params: %{"offset" => 0, "limit" => 3}} = conn ->
        send(test_pid, {:first, self()})

        receive do
          :go ->
            response = %{
              "ok" => true,
              "result" => [
                %{"update_id" => 1},
                %{"update_id" => 2}
              ]
            }

            Req.Test.json(conn, response)

          :crash ->
            raise "UnexpectedError!"
        end

      %{body_params: %{"offset" => 3, "limit" => 1}} ->
        send(test_pid, :second)
        Process.sleep(:infinity)
    end)

    start_broadway()

    assert_receive {:first, producer_pid}
    send(producer_pid, :crash)
    assert_receive {:first, producer_pid}
    send(producer_pid, :go)

    assert_receive {:message_handled, %{"update_id" => 2}, processor_pid}
    assert_receive :second

    send(processor_pid, :go)
    assert_receive {:message_handled, %{"update_id" => 1}, _}
    send(processor_pid, :go)
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
                  token: "fake_token",
                  plug: {Req.Test, MockClient},
                  task_supervisor: __MODULE__.Supervisor},
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
