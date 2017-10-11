defmodule VpsAdmin.Persistence.Transaction.ProcessesTest do
  use ExUnit.Case

  alias VpsAdmin.Persistence.Transaction.Processes

  test "process registration" do
    {:ok, pid1} = Agent.start_link(fn -> nil end)
    {:ok, pid2} = Agent.start_link(fn -> nil end)

    refute Processes.chain_id(pid1)
    refute Processes.chain_id(pid2)

    Processes.add(pid1, 123)
    Processes.add(pid2, 456)

    assert Processes.chain_id(pid1) == 123
    assert Processes.chain_id(pid2) == 456

    :ok = Processes.remove(pid1)

    refute Processes.chain_id(pid1)
    assert Processes.chain_id(pid2) == 456

    :ok = Processes.remove(pid2)

    refute Processes.chain_id(pid2)

    Agent.stop(pid1)
    Agent.stop(pid2)
  end

  test "automatic dead-process removal" do
    {:ok, pid1} = Agent.start_link(fn -> nil end)
    {:ok, pid2} = Agent.start_link(fn -> nil end)

    refute Processes.chain_id(pid1)
    refute Processes.chain_id(pid2)

    Processes.add(pid1, 123)
    Processes.add(pid2, 456)

    assert Processes.chain_id(pid1) == 123
    assert Processes.chain_id(pid2) == 456

    Agent.stop(pid1)

    # Give the server process time to process the EXIT message
    Process.sleep(100)

    refute Processes.chain_id(pid1)
    assert Processes.chain_id(pid2) == 456

    Agent.stop(pid2)
    Process.sleep(100)

    refute Processes.chain_id(pid2)
  end

  test "server crash takes down registered processes" do
    {:ok, pid1} = Agent.start(fn -> nil end)
    {:ok, pid2} = Agent.start(fn -> nil end)

    refute Processes.chain_id(pid1)
    refute Processes.chain_id(pid2)

    Processes.add(pid1, 123)
    Processes.add(pid2, 456)

    assert Processes.chain_id(pid1) == 123
    assert Processes.chain_id(pid2) == 456

    GenServer.stop(Processes, :test)

    refute Process.alive?(pid1)
    refute Process.alive?(pid2)
  end

  test "crash in register process does not take down the server" do
    {:ok, pid1} = Agent.start(fn -> nil end)
    {:ok, pid2} = Agent.start(fn -> nil end)

    refute Processes.chain_id(pid1)
    refute Processes.chain_id(pid2)

    Processes.add(pid1, 123)
    Processes.add(pid2, 456)

    assert Processes.chain_id(pid1) == 123
    assert Processes.chain_id(pid2) == 456

    ref = Process.monitor(Processes)
    Agent.stop(pid1, :test)
    refute_receive {:DOWN, ^ref, :process, _pid, _reason}

    Agent.stop(pid2, :normal)
    refute_receive {:DOWN, ^ref, :process, _pid, _reason}

    Process.demonitor(ref)
  end
end
