defmodule VpsAdmin.Transactional.RunStateTest do
  use ExUnit.Case

  alias VpsAdmin.Transactional.{Chain, Command, RunState, Transaction}

  test "sorting transactions into respective fields" do
    chain = Chain.new(10, :all_or_none, :executing, [
      Transaction.new(100, :all_or_none, :queued, []),
      Transaction.new(101, :all_or_none, :executing, []),
      Transaction.new(102, :all_or_none, :done, []),
      Transaction.new(103, :all_or_none, :failed, []),
      Transaction.new(104, :all_or_none, :rollingback, []),
      Transaction.new(105, :all_or_none, :rolledback, []),
    ])

    rs = RunState.new(chain)

    assert rs.queued == [100]
    assert rs.executing == [101]
    assert rs.done == [102]
    assert rs.failed == [103]
    assert rs.rollingback == [104]
    assert rs.rolledback == [105]
  end

  test "sorting commands into respective fields" do
    t = Transaction.new(100, :all_or_none, :queued, [
      Command.new(1000, :queued, Node.self, nil, %{}),
      Command.new(1001, :executing, Node.self, nil, %{}),
      Command.new(1002, :done, Node.self, nil, %{}),
      Command.new(1003, :failed, Node.self, nil, %{}),
      Command.new(1004, :rollingback, Node.self, nil, %{}),
      Command.new(1005, :rolledback, Node.self, nil, %{}),
    ])

    rs = RunState.new(t)

    assert rs.queued == [1000]
    assert rs.executing == [1001]
    assert rs.done == [1002]
    assert rs.failed == [1003]
    assert rs.rollingback == [1004]
    assert rs.rolledback == [1005]
  end
end
