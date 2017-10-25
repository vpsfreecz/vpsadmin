defmodule VpsAdmin.Transactional.Strategy do
  @moduledoc """
  Behaviour for planning execution of transactions and their commands.

  Strategies determine what transactions/commands should be run or rollbacked,
  based on `VpsAdmin.Transaction.RunState`. Strategies work on both transactions
  and commands.
  """

  alias VpsAdmin.Transactional.{RunState, Strategy}

  @doc """
  Return a new plan based on `runstate`.

  This function advances the plan if possible, i.e. if the execution
  queue is empty and there are transactions waiting, execute them.
  If there is nothing to change, the original run state is returned.
  """
  @callback plan(
    runstate :: RunState.t
  ) :: {to_execute :: list, to_rollback :: list, RunState.t}

  @doc """
  Update and return a plan when an executed item changes state.

  This function is called when an executed transaction/command changes
  state, i.e. finishes or fails. The strategy decides what to do next,
  whether to continue or roll back and what to execute next.
  """
  @callback update(
    runstate :: RunState.t,
    item :: term,
    status :: atom
  ) :: {to_execute :: list, to_rollback :: list, RunState.t}

  def plan(strategy, runstate) do
    module(strategy).plan(runstate)
  end

  def update(strategy, runstate, item, status) do
    module(strategy).update(runstate, item, status)
  end

  defp module(:all_or_none), do: Strategy.AllOrNone
end
