defmodule VpsAdmin.Transactional.Strategy.AllOrNoneTest do
  use ExUnit.Case

  alias VpsAdmin.Transactional.Strategy.AllOrNone
  alias VpsAdmin.Transactional.RunState

  describe "planning" do
    test "executes items one by one" do
      rs = %RunState{state: :executing, executing: [], queued: [1, 2, 3]}

      assert {[1], [], %RunState{
        state: :executing,
        executing: [1],
        queued: [2, 3],
      } = rs} = AllOrNone.plan(rs)

      assert {[], [], ^rs} = AllOrNone.plan(rs)
    end

    test "rolls back items one by one" do
      rs = %RunState{state: :rollingback, executing: [], queued: [1, 2, 3]}

      assert {[], [1], %RunState{
        state: :rollingback,
        rollingback: [1],
        queued: [2, 3],
      } = rs} = AllOrNone.plan(rs)

      assert {[], [], ^rs} = AllOrNone.plan(rs)
    end

    test "finished when queue is empty" do
      rs = %RunState{state: :executing, executing: [], queued: []}

      assert {:done, %RunState{
        state: :done,
        executing: [],
        queued: [],
      }} = AllOrNone.plan(rs)

      rs = %RunState{state: :rollingback, rollingback: [], queued: []}

      assert {:rolledback, %RunState{
        state: :rolledback,
        executing: [],
        queued: [],
      }} = AllOrNone.plan(rs)
    end

    test "executes queued transactions" do
      rs = %RunState{state: :queued, executing: [], queued: [1, 2, 3]}

      assert {[1], [], %RunState{
        state: :executing,
        executing: [1],
        queued: [2, 3],
      } = rs} = AllOrNone.plan(rs)

      assert {[], [], ^rs} = AllOrNone.plan(rs)
    end
  end

  describe "updates" do
    test "execution advances" do
      rs = %RunState{state: :executing, executing: [1], queued: [2, 3]}

      assert {[2], [], %RunState{
        state: :executing,
        executing: [2],
        queued: [3],
        done: [1],
      }} = AllOrNone.update(rs, 1, :done)
    end

    test "rollback advances" do
      rs = %RunState{state: :rollingback, rollingback: [3], queued: [2, 1]}

      assert {[], [2], %RunState{
        state: :rollingback,
        rollingback: [2],
        queued: [1],
        rolledback: [3]
      }} = AllOrNone.update(rs, 3, :rolledback)
    end

    test "transition to rollback on error" do
      rs = %RunState{state: :executing, executing: [3], queued: [4], done: [2, 1]}

      assert {[], [3], %RunState{
        state: :rollingback,
        executing: [],
        rollingback: [3],
        queued: [2, 1],
      }} = AllOrNone.update(rs, 3, :failed)
    end

    test "error in rollback results in fatal error" do
      rs = %RunState{state: :rollingback, rollingback: [3], queued: [2, 1]}

      assert {:fatal, %RunState{state: :fatal}} = AllOrNone.update(rs, 3, :failed)
    end

    test "non-updates do nothing" do
      rs = %RunState{state: :executing, executing: [1], queued: [2, 3]}
      assert {[], [], ^rs} = AllOrNone.update(rs, 1, :executing)

      rs = %RunState{state: :rollingback, rollingback: [3], queued: [2, 1]}
      assert {[], [], ^rs} = AllOrNone.update(rs, 3, :rollingback)
    end
  end
end
