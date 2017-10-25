defmodule VpsAdmin.Transactional.Chain.Executor do
  @moduledoc "Process handling chain execution"

  use GenServer, restart: :transient

  alias VpsAdmin.Transactional
  alias VpsAdmin.Transactional.{RunState, State, Strategy, Transaction}

  require Logger

  # Client API
  def start_link(chain_id) do
    GenServer.start_link(__MODULE__, chain_id, name: via_tuple(chain_id))
  end

  def update(chain_id, transaction_id, status) do
    GenServer.cast(via_tuple(chain_id), {:update, transaction_id, status})
  end

  def via_tuple(chain_id) when is_integer(chain_id) do
    {:via, Registry, {Transactional.Registry, {:chain, chain_id}}}
  end

  def via_tuple(chain), do: via_tuple(chain.id)

  # Server implementation
  def init(chain_id) do
    Logger.debug "Started chain executor #{chain_id}"

    send(self(), :chain_startup)

    chain = State.get_chain(chain_id)

    {:ok, %{
      id: chain_id,
      strategy: chain.strategy,
      runstate: RunState.new(chain),
    }}
  end

  def handle_info(:chain_startup, state) do
    Logger.debug "Initializing chain process #{state.id}"

    case schedule(state, Strategy.plan(state.strategy, state.runstate)) do
      {:ok, state} ->
        {:noreply, state}

      {:done, state} ->
        {:stop, :normal, state}
    end
  end

  def handle_cast({:update, t_id, status}, state) do
    Logger.debug "Chain #{state.id} received transaction update from #{t_id}: #{status}"

    # Save transaction's status
    State.update(state.id, t_id, status)

    case schedule(state, Strategy.update(state.strategy, state.runstate, t_id, status)) do
      {:ok, state} ->
        {:noreply, state}

      {:done, state} ->
        {:stop, :normal, state}
    end
  end

  defp schedule(state, result) do
    Logger.debug "Scheduling based on #{inspect(result)}"

    case result do
      {:done, runstate} ->
        State.update(state.id, runstate.state)
        {:done, state}

      {:failed, runstate} ->
        State.update(state.id, runstate.state)
        {:done, state}

      {:rolledback, runstate} ->
        State.update(state.id, runstate.state)
        {:done, state}

      {to_execute, to_rollback, runstate} ->
        State.update(state.id, runstate.state)
        execute(state.id, to_execute)
        rollback(state.id, to_rollback)
        {:ok, %{state | runstate: runstate}}
    end
  end

  defp execute(chain_id, transactions) do
    for t <- transactions do
      State.update(chain_id, t, :executing)
      Transaction.execute(chain_id, t)
    end
  end

  defp rollback(chain_id, transactions) do
    for t <- transactions do
      State.update(chain_id, t, :rollingback)
      Transaction.rollback(chain_id, t)
    end
  end
end
