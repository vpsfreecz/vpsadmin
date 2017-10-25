defmodule VpsAdmin.Transactional.StateTest do
  use ExUnit.Case

  alias VpsAdmin.Transactional
  alias VpsAdmin.Transactional.{Chain, Command, State, Transaction}

  test "there can be only one state per chain" do
    chain = Chain.new(10, :all_or_none, :executing, [])
    {:ok, pid} = State.start_link(chain)

    assert Registry.lookup(Transactional.Registry, {:chain_state, 10}) == [{pid, nil}]
    assert {:error, {:already_started, ^pid}} = State.start_link(chain)
  end

  test "getting chain state" do
    chain = Chain.new(10, :all_or_none, :executing, [])
    {:ok, _pid} = State.start_link(chain)

    assert ^chain = State.get_chain(10)
  end

  test "getting transaction state" do
    t = Transaction.new(100, :all_or_none, :queued, [])
    chain = Chain.new(10, :all_or_none, :executing, [t])
    {:ok, _pid} = State.start_link(chain)

    assert ^t = State.get_transaction(10, 100)
  end

  test "getting command state" do
    c = Command.new(1000, :queued, Node.self, nil, %{})
    chain = Chain.new(10, :all_or_none, :executing, [
      Transaction.new(100, :all_or_none, :queued, [c])
    ])
    {:ok, _pid} = State.start_link(chain)

    assert ^c = State.get_command(10, 100, 1000)
  end

  test "updating chain state" do
    chain = Chain.new(10, :all_or_none, :executing, [])
    {:ok, _pid} = State.start_link(chain)

    assert ^chain = State.get_chain(10)
    State.update(10, :rollingback)
    assert %Chain{state: :rollingback} = State.get_chain(10)
  end

  test "updating transaction state" do
    t = Transaction.new(100, :all_or_none, :queued, [])
    chain = Chain.new(10, :all_or_none, :executing, [t])
    {:ok, _pid} = State.start_link(chain)

    assert ^t = State.get_transaction(10, 100)
    State.update(10, 100, :done)
    assert %Transaction{state: :done} = State.get_transaction(10, 100)
  end

  test "updating command state" do
    c = Command.new(1000, :queued, Node.self, nil, %{})
    chain = Chain.new(10, :all_or_none, :executing, [
      Transaction.new(100, :all_or_none, :queued, [c])
    ])
    {:ok, _pid} = State.start_link(chain)

    assert ^c = State.get_command(10, 100, 1000)
    State.update(10, 100, 1000, :failed)
    assert %Command{state: :failed} = State.get_command(10, 100, 1000)
  end

  test "process stops when chain is finished" do
    chain = Chain.new(10, :all_or_none, :executing, [])

    for state <- ~w(done failed rolledback)a do
      {:ok, pid} = State.start_link(chain)

      assert ^chain = State.get_chain(10)
      State.update(10, state)
      Process.sleep(10)
      refute Process.alive?(pid)
    end
  end

  test "does not crash when updating invalid transaction" do
    chain = Chain.new(10, :all_or_none, :executing, [])
    {:ok, pid} = State.start_link(chain)

    assert State.update(10, 100, :done) == :ok
    Process.sleep(10)
    assert Process.alive?(pid)
  end

  test "does not crash when updating invalid command" do
    chain = Chain.new(10, :all_or_none, :executing, [])
    {:ok, pid} = State.start_link(chain)

    assert State.update(10, 100, 1000, :done) == :ok
    Process.sleep(10)
    assert Process.alive?(pid)
  end
end
