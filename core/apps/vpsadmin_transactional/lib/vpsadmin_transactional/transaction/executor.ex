defmodule VpsAdmin.Transactional.Transaction.Executor do
  @moduledoc "Process handling transaction execution"

  use GenServer, restart: :transient

  alias VpsAdmin.Transactional
  alias VpsAdmin.Transactional.{Chain, Command, Queue, State, Strategy}

  require Logger

  # Client API
  def start_link(chain_id, transaction_id, action) do
    GenServer.start_link(
      __MODULE__,
      {chain_id, transaction_id, action},
      name: via_tuple(transaction_id)
    )
  end

  def via_tuple(transaction_id) when is_integer(transaction_id) do
    {:via, Registry, {Transactional.Registry, {:transaction, transaction_id}}}
  end

  # Server implementation
  def init({chain_id, transaction_id, action}) do
    send(self(), :transaction_startup)

    t = Transactional.State.get_transaction(chain_id, transaction_id)

    {:ok, %{
      id: transaction_id,
      chain_id: chain_id,
      strategy: t.strategy,
      runstate: Transactional.RunState.new(t),
    }}
  end

  def handle_info(:transaction_startup, state) do
    Logger.debug "Started process for transaction ##{state.id}"

    case schedule(state, Strategy.plan(state.strategy, state.runstate)) do
      {:ok, state} ->
        {:noreply, state}

      {:done, state} ->
        {:stop, :normal, state}
    end
  end

  def handle_cast({:queue, id, :done, :normal}, state) do
    target_state = if state.runstate.state == :executing do
      :done
    else
      :rolledback
    end

    # Update command's state
    State.update(state.chain_id, state.id, id, target_state)

    case schedule(state, Strategy.update(state.strategy, state.runstate, id, target_state)) do
      {:ok, state} ->
        {:noreply, state}

      {:done, state} ->
        {:stop, :normal, state}
    end
  end

  def handle_cast({:queue, id, :done, _error}, state) do
    # Update command's state
    State.update(state.chain_id, state.id, id, :failed)

    case schedule(state, Strategy.update(state.strategy, state.runstate, id, :failed)) do
      {:ok, state} ->
        {:noreply, state}

      {:done, state} ->
        {:stop, :normal, state}
    end
  end

  def handle_cast({:queue, id, :executing}, state) do
    # State is already updated by execute/3 and rollback/3, but it would
    # be nice to differentiate between being enqueued and actually executing
    {:noreply, state}
  end

  defp schedule(state, result) do
    # TODO: we should send state update only when it's actually changed,
    # not always
    case result do
      {:done, runstate} ->
        Chain.Executor.update(state.chain_id, state.id, :done)
        {:done, state}

      {:rolledback, runstate} ->
        Chain.Executor.update(state.chain_id, state.id, :rolledback)
        {:done, state}

      {:failed, runstate} ->
        Chain.Executor.update(state.chain_id, state.id, :failed)
        {:done, state}

      {to_execute, to_rollback, runstate} ->
        Chain.Executor.update(state.chain_id, state.id, runstate.state)
        execute(state.chain_id, state.id, to_execute)
        rollback(state.chain_id, state.id, to_rollback)
        {:ok, %{state | runstate: runstate}}
    end
  end

  defp execute(chain_id, transaction_id, commands) do
    for c <- commands do
      Logger.debug "Enqueueing command #{c} for execution"
      State.update(chain_id, transaction_id, c, :executing)
      Queue.enqueue(
        :default,
        c,
        {Command, :start_link, [chain_id, transaction_id, c]},
        via_tuple(transaction_id)
      )
    end
  end

  defp rollback(chain_id, transaction_id, commands) do
    for c <- commands do
      Logger.debug "Enqueueing command #{c} for rollback"
      State.update(chain_id, transaction_id, c, :rollingback)
      Queue.enqueue(
        :default,
        c,
        {Command, :start_link, [chain_id, transaction_id, c]},
        via_tuple(transaction_id)
      )
    end
  end
end
