defmodule VpsAdmin.Base.MonitorTest do
  use ExUnit.Case

  alias VpsAdmin.Base.Monitor

  test "can subscribe to anything" do
    {:ok, m} = Monitor.start_link()
    assert :ok = Monitor.subscribe(m, :myevent)
    assert [{:myevent, self()}] == Monitor.subscribers(m)
  end

  test "can unsubscribe" do
    {:ok, m} = Monitor.start_link()
    assert :ok = Monitor.subscribe(m, :myevent)
    assert [{:myevent, self()}] == Monitor.subscribers(m)
    assert :ok = Monitor.unsubscribe(m, :myevent)
    assert [] == Monitor.subscribers(m)
  end

  test "unsunscribes dead processes" do
    {:ok, m} = Monitor.start_link()

    task = Task.async(fn ->
      assert :ok = Monitor.subscribe(m, :myevent)
      assert [{:myevent, self()}] == Monitor.subscribers(m)
      :ok
    end)

    assert :ok = Task.await(task)
    assert [] == Monitor.subscribers(m)
  end

  test "can publish anything" do
    {:ok, m} = Monitor.start_link()
    Monitor.publish(m, :myevent, :myarg)
  end

  test "can read past events" do
    {:ok, m} = Monitor.start_link()
    Monitor.subscribe(m, :myevent)
    Monitor.subscribe(m, :myevent2)

    Monitor.publish(m, :myevent, :myarg)
    assert {:myevent, :myarg} = Monitor.read_one(m)

    Monitor.publish(m, :myevent2, :myarg2)
    assert {:myevent2, :myarg2} = Monitor.read_one(m)
  end

  test "can read future events" do
    {:ok, m} = Monitor.start_link()
    Monitor.subscribe(m, :myevent)

    task =
      Task.async(fn ->
        Process.sleep(500)
        Monitor.publish(m, :myevent, :myarg)
        :ok
      end)

    assert {:myevent, :myarg} = Monitor.read_one(m)
    assert :ok = Task.await(task)
  end

  test "event filtering" do
    {:ok, m} = Monitor.start_link()
    interval = 1..10

    tasks = for x <- interval do
      Task.async(fn ->
        Monitor.subscribe(m, {:myevent, x})
        Monitor.read_one(m)
      end)
    end

    # Wait for the tasks to subscribe
    Process.sleep(200)

    for x <- Enum.shuffle(interval) do
      Monitor.publish(m, {:myevent, x}, x)
    end

    expected = for x <- interval, do: {{:myevent, x}, x}
    result = Enum.map(tasks, &Task.await/1)
    assert expected == result
  end

  test "same event ordering" do
    {:ok, m} = Monitor.start_link()

    Monitor.subscribe(m, :myevent)
    for x <- 1..10, do: Monitor.publish(m, :myevent, x)
    for x <- 1..10, do: assert {:myevent, x} == Monitor.read_one(m)
  end

  test "different event ordering" do
    {:ok, m} = Monitor.start_link()

    for x <- 1..10, do: Monitor.subscribe(m, {:myevent, x})

    seq = Enum.shuffle(1..10)

    for x <- seq, do: Monitor.publish(m, {:myevent, x}, x)
    for x <- seq, do: assert {{:myevent, x}, x} == Monitor.read_one(m)
  end
end
