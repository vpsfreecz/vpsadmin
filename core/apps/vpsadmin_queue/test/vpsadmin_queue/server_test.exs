defmodule VpsAdmin.Queue.ServerTest do
  use ExUnit.Case

  alias VpsAdmin.Queue
  alias VpsAdmin.Queue.Server

  defmodule Worker do
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

  setup do
    start_supervised!({Registry, keys: :unique, name: Queue.Registry})
    :ok
  end

  test "is empty on start" do
    {:ok, _pid} = Server.start_link({:myqueue, 2})
    status = Server.status(:myqueue)

    assert status.executing == 0
    assert status.queued == 0
    assert status.current_size == 2
    assert status.max_size == 2
  end

  test "has configurable size" do
    {:ok, _pid} = Server.start_link({:myqueue1, 1})
    assert Server.status(:myqueue1).current_size == 1
    assert Server.status(:myqueue1).max_size == 1

    {:ok, _pid} = Server.start_link({:myqueue2, 4})
    assert Server.status(:myqueue2).current_size == 4
    assert Server.status(:myqueue2).max_size == 4
  end

  test "notifies when execution starts" do
    {:ok, _pid} = Server.start_link({:myqueue, 1})

    :ok =
      Server.enqueue(
        :myqueue,
        :test,
        {Worker, :start_link, [fn -> {:ok, :normal, 200} end]},
        self()
      )

    assert_receive {_, {:queue, :test, :executing}}
  end

  test "notifies when execution finishes" do
    {:ok, _pid} = Server.start_link({:myqueue, 1})

    :ok =
      Server.enqueue(
        :myqueue,
        :test,
        {Worker, :start_link, [fn -> {:ok, :timeout, 200} end]},
        self()
      )

    assert_receive {_, {:queue, :test, :executing}}
    assert_receive {_, {:queue, :test, :done, :timeout}}, 500
  end

  test "does not crash if process cannot be launched" do
    {:ok, _pid} = Server.start_link({:myqueue, 1})

    :ok =
      Server.enqueue(
        :myqueue,
        :test,
        {Worker, :start_link, [fn -> {:stop, :error} end]},
        self()
      )

    assert is_map(Server.status(:myqueue))
  end

  test "does not crash if the launched process crashes" do
    {:ok, _pid} = Server.start_link({:myqueue, 1})

    :ok =
      Server.enqueue(
        :myqueue,
        :test,
        {Worker, :start_link, [fn -> {:ok, :testcrash, 200} end]},
        self()
      )

    assert_receive {_, {:queue, :test, :done, :testcrash}}, 500
  end

  test "items are enqueued if the queue is full" do
    {:ok, _pid} = Server.start_link({:myqueue, 4})

    for _ <- 1..10 do
      :ok =
        Server.enqueue(
          :myqueue,
          :test,
          {Worker, :start_link, [fn -> {:ok, :normal, 100} end]},
          self()
        )
    end

    status = Server.status(:myqueue)
    assert status.executing == 4
    assert status.queued == 6

    Process.sleep(120)

    status = Server.status(:myqueue)
    assert status.executing == 4
    assert status.queued == 2

    Process.sleep(120)

    status = Server.status(:myqueue)
    assert status.executing == 2
    assert status.queued == 0

    Process.sleep(120)

    status = Server.status(:myqueue)
    assert status.executing == 0
    assert status.queued == 0
  end

  describe "slot reservation acquiring" do
    test "can reserve free slots" do
      {:ok, _pid} = Server.start_link({:myqueue, 4})
      status = Server.status(:myqueue)

      assert status.current_size == 4
      assert status.max_size == 4

      Server.reserve(:myqueue, :myname, 2, self())
      assert_receive {_, {:queue, :myname, :reserved}}, 500

      status = Server.status(:myqueue)
      assert status.current_size == 2
      assert status.max_size == 4

      assert :ok = Server.reserve(:myqueue, :myname, 2, self())
      assert_receive {_, {:queue, :myname, :reserved}}, 500

      status = Server.status(:myqueue)
      assert status.current_size == 0
      assert status.max_size == 4
    end

    test "can reserve only allowed slots" do
      {:ok, _pid} = Server.start_link({:myqueue, 4})

      assert {:error, :badreservation} = Server.reserve(:myqueue, :myname, 0, self())
      assert {:error, :badreservation} = Server.reserve(:myqueue, :myname, 5, self())

      assert :ok = Server.reserve(:myqueue, :myname, 4, self())
      assert_receive {_, {:queue, :myname, :reserved}}, 500

      assert {:error, :badreservation} = Server.reserve(:myqueue, :myname, 1, self())
    end
  end

  describe "slot reservation usage" do
    test "can reserve a slot and use it" do
      {:ok, _pid} = Server.start_link({:myqueue, 1})

      assert :ok = Server.reserve(:myqueue, :myname, 1, self())
      assert_receive {_, {:queue, :myname, :reserved}}, 500

      assert :ok =
        Server.enqueue(
          :myqueue,
          :test,
          {Worker, :start_link, [fn -> {:ok, :timeout, 100} end]},
          self(),
          name: :myname
        )

      assert_receive {_, {:queue, :test, :executing}}
      assert_receive {_, {:queue, :test, :done, :timeout}}, 500
    end

    test "reserved slot cannot be stolen" do
      {:ok, _pid} = Server.start_link({:myqueue, 1})

      assert :ok = Server.reserve(:myqueue, :myname, 1, self())
      assert_receive {_, {:queue, :myname, :reserved}}, 500

      assert :ok =
        Server.enqueue(
          :myqueue,
          :test,
          {Worker, :start_link, [fn -> {:ok, :timeout, 10} end]},
          self()
        )

      refute_receive {_, {:queue, :test, :executing}}, 500
      refute_receive {_, {:queue, :test, :done, :timeout}}, 500
    end
  end

  describe "slot reservation releasing" do
    test "can release reserved slots" do
      {:ok, _pid} = Server.start_link({:myqueue, 4})

      status = Server.status(:myqueue)
      assert status.current_size == 4
      assert status.max_size == 4

      Server.reserve(:myqueue, :myname, 2, self())
      assert_receive {_, {:queue, :myname, :reserved}}, 500

      status = Server.status(:myqueue)
      assert status.current_size == 2
      assert status.max_size == 4

      assert :ok = Server.release(:myqueue, :myname, 2)

      status = Server.status(:myqueue)
      assert status.current_size == 4
      assert status.max_size == 4
    end

    test "cannot release non-existing reservation" do
      {:ok, _pid} = Server.start_link({:myqueue, 4})

      assert {:error, :notfound} = Server.release(:myqueue, :myname, 1)
    end

    test "cannot release more than reserved" do
      {:ok, _pid} = Server.start_link({:myqueue, 4})

      assert :ok = Server.reserve(:myqueue, :myname, 2, self())
      assert_receive {_, {:queue, :myname, :reserved}}, 500

      assert {:error, :invalid} = Server.release(:myqueue, :myname, 3)

      status = Server.status(:myqueue)
      assert status.current_size == 2
      assert status.max_size == 4
    end

    test "cannot release less than one slot" do
      {:ok, _pid} = Server.start_link({:myqueue, 4})

      assert :ok = Server.reserve(:myqueue, :myname, 2, self())
      assert_receive {_, {:queue, :myname, :reserved}}, 500

      assert {:error, :invalid} = Server.release(:myqueue, :myname, -1)
      assert {:error, :invalid} = Server.release(:myqueue, :myname, 0)

      status = Server.status(:myqueue)
      assert status.current_size == 2
      assert status.max_size == 4
    end
  end
end
