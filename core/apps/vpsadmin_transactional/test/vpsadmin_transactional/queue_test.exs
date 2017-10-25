defmodule VpsAdmin.Transactional.QueueTest do
  use ExUnit.Case

  alias VpsAdmin.Transactional.Queue

  defmodule Server do
    use GenServer

    def start_link(arg) do
      GenServer.start_link(__MODULE__, arg)
    end

    def init(arg) do
      arg.()
    end

    def handle_info(:timeout, status) do
      {:stop, status, status}
    end
  end

  test "is empty on start" do
    {:ok, _pid} = Queue.start_link({:myqueue, 2})
    status = Queue.status(:myqueue)

    assert status.executing == 0
    assert status.queued == 0
    assert status.size == 2
  end

  test "has configurable size" do
    {:ok, _pid} = Queue.start_link({:myqueue1, 1})
    assert Queue.status(:myqueue1).size == 1

    {:ok, _pid} = Queue.start_link({:myqueue2, 4})
    assert Queue.status(:myqueue2).size == 4
  end

  test "notifies when execution starts" do
    {:ok, _pid} = Queue.start_link({:myqueue, 1})

    :ok = Queue.enqueue(
      :myqueue,
      :test,
      {Server, :start_link, [fn -> {:ok, nil, 200} end]},
      self()
    )

    assert_receive {_, {:queue, :test, :executing}}
  end

  test "notifies when execution finishes" do
    {:ok, _pid} = Queue.start_link({:myqueue, 1})

    :ok = Queue.enqueue(
      :myqueue,
      :test,
      {Server, :start_link, [fn -> {:ok, :timeout, 200} end]},
      self()
    )

    assert_receive {_, {:queue, :test, :done, :timeout}}, 250
  end

  test "does not crash if process cannot be launched" do
    {:ok, _pid} = Queue.start_link({:myqueue, 1})

    :ok = Queue.enqueue(
      :myqueue,
      :test,
      {Server, :start_link, [fn -> {:stop, :error} end]},
      self()
    )

    assert is_map(Queue.status(:myqueue))
  end

  test "does not crash if the launched process crashes" do
    {:ok, _pid} = Queue.start_link({:myqueue, 1})

    :ok = Queue.enqueue(
      :myqueue,
      :test,
      {Server, :start_link, [fn -> {:ok, :testcrash, 200} end]},
      self()
    )

    assert_receive {_, {:queue, :test, :done, :testcrash}}, 250
  end

  test "items are enqueued if the queue is full" do
    {:ok, _pid} = Queue.start_link({:myqueue, 4})

    for _ <- 1..10 do
      :ok = Queue.enqueue(
        :myqueue,
        :test,
        {Server, :start_link, [fn -> {:ok, nil, 100} end]},
        self()
      )
    end

    status = Queue.status(:myqueue)
    assert status.executing == 4
    assert status.queued == 6

    Process.sleep(120)

    status = Queue.status(:myqueue)
    assert status.executing == 4
    assert status.queued == 2

    Process.sleep(120)

    status = Queue.status(:myqueue)
    assert status.executing == 2
    assert status.queued == 0

    Process.sleep(120)

    status = Queue.status(:myqueue)
    assert status.executing == 0
    assert status.queued == 0
  end
end
