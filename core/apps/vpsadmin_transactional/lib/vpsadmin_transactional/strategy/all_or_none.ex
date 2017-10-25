defmodule VpsAdmin.Transactional.Strategy.AllOrNone do
  @moduledoc """
  All or none execution strategy.

  This strategy executes available transactions/commands one by one. On failure,
  all executed items are rolled back.
  """

  alias VpsAdmin.Transactional.RunState

  ### Planning
  # Initial call
  def plan(%RunState{state: :queued, executing: [], queued: [h|t]} = runstate) do
    {[h], [], %{runstate | state: :executing, executing: [h], queued: t}}
  end

  # Execution queue empty, run available commands
  def plan(%RunState{state: :executing, executing: [], queued: [h|t]} = runstate) do
    {[h], [], %{runstate | executing: [h], queued: t}}
  end

  def plan(%RunState{state: :rollingback, rollingback: [], queued: [h|t]} = runstate) do
    {[], [h], %{runstate | rollingback: [h], queued: t}}
  end

  # Execution queue full
  def plan(%RunState{state: :executing, executing: [_]} = runstate) do
    {[], [], runstate}
  end

  def plan(%RunState{state: :rollingback, rollingback: [_]} = runstate) do
    {[], [], runstate}
  end

  # Execution finished, queue is empty
  def plan(%RunState{state: :executing, executing: [], queued: []} = runstate) do
    {:done, %{runstate | state: :done}}
  end

  def plan(%RunState{state: :rollingback, rollingback: [], queued: []} = runstate) do
    {:rolledback, %{runstate | state: :rolledback}}
  end

  # Fatal error
  def plan(%RunState{state: :fatal} = runstate) do
    {:fatal, %{runstate | state: :fatal}}
  end

  ### Updates
  # Execution update
  def update(%RunState{state: :executing, executing: [item]} = runstate, item, :done) do
    %{runstate | executing: [], done: [item | runstate.done]}
    |> plan()
  end

  def update(%RunState{state: :executing, executing: [item]} = runstate, item, :failed) do
    %{runstate | executing: [], state: :rollingback, queued: [item | runstate.done]}
    |> plan()
  end

  # This update here is questionable, because we did not tell anyone to initiate
  # a rollback. Chain receives this notification when transaction command fails
  # and so the transaction decides to roll back. It does not wait for the chain
  # strategy to decide whether it should roll back or not. So the strategy just
  # accepts this decision.
  def update(%RunState{state: :executing, executing: [item]} = runstate, item, :rollingback) do
    %{runstate |
      executing: [],
      state: :rollingback,
      rollingback: [item],
      queued: runstate.done
    } |> plan()
  end

  def update(%RunState{state: :executing, executing: [item]} = runstate, item, :executing) do
    {[], [], runstate}
  end

  # Rollback update
  def update(%RunState{state: :rollingback, rollingback: [item]} = runstate, item, :rolledback) do
    %{runstate | rollingback: [], rolledback: [item | runstate.rolledback]}
    |> plan()
  end

  def update(%RunState{state: :rollingback, rollingback: [item]} = runstate, item, :failed) do
    %{runstate | rollingback: [], state: :fatal, queued: []}
    |> plan()
  end

  def update(%RunState{state: :rollingback, rollingback: [item]} = runstate, item, :rollingback) do
    {[], [], runstate}
  end
end
