defmodule VpsAdmin.Transactional.State do
  @moduledoc """
  Process that keeps track of transaction chain state.

  All execution progress is reported to this process, which stores the state
  once for every chain on each node. Whenever execution process starts
  or restarts on crash, it gets chain state from this process.

  If this process crashes, the state is permanently lost, so until we store
  the state persistently, the process cannot be restarted, as it would give
  invalid values.
  """

  use GenServer, restart: :temporary

  require Logger

  alias VpsAdmin.Transactional
  alias VpsAdmin.Transactional.{Chain, Transaction}

  # Client API
  @spec start_link(chain :: Chain.t) :: GenServer.on_start
  def start_link(chain) do
    GenServer.start_link(__MODULE__, chain, name: via_tuple(chain))
  end

  @spec get_chain(chain_id :: integer) :: Chain.t
  def get_chain(chain_id) do
    GenServer.call(via_tuple(chain_id), :get_chain)
  end

  @spec get_transaction(chain_id :: integer, transaction_id :: integer) :: Transaction.t
  def get_transaction(chain_id, transaction_id) do
    GenServer.call(via_tuple(chain_id), {:get_transaction, transaction_id})
  end

  @spec get_command(
    chain_id :: integer,
    transaction_id :: integer,
    command_id :: integer
  ) :: Command.t
  def get_command(chain_id, transaction_id, command_id) do
    GenServer.call(via_tuple(chain_id), {:get_command, transaction_id, command_id})
  end

  def update(chain_id, status) do
    GenServer.cast(via_tuple(chain_id), {:update, status})
  end

  def update(chain_id, transaction_id, status) do
    GenServer.cast(via_tuple(chain_id), {:update, transaction_id, status})
  end

  def update(chain_id, transaction_id, cmd_id, status) do
    GenServer.cast(via_tuple(chain_id), {:update, transaction_id, cmd_id, status})
  end

  def via_tuple(chain_id) when is_integer(chain_id) do
    {:via, Registry, {Transactional.Registry, {:chain_state, chain_id}}}
  end

  def via_tuple(chain), do: via_tuple(chain.id)

  # Server implementation
  def init(chain) do
    Logger.debug "Initializing chain state process #{chain.id}"
    {:ok, chain}
  end

  def handle_call(:get_chain, _from, chain) do
    {:reply, chain, chain}
  end

  def handle_call({:get_transaction, t_id}, _from, chain) do
    case find_transaction(chain, t_id) do
      nil ->
        {:reply, {:error, :not_found}, chain}

      t ->
        {:reply, t, chain}
    end
  end

  def handle_call({:get_command, t_id, cmd_id}, _from, chain) do
    case find_transaction(chain, t_id) do
      nil ->
        {:reply, {:error, :transaction_not_found}, chain}

      t ->
        case find_command(t, cmd_id) do
          nil ->
            {:reply, {:error, :not_found}, chain}

          c ->
            {:reply, c, chain}
        end
    end
  end

  def handle_cast({:update, status}, chain) do
    chain = %{chain | state: status}

    case status do
      s when s in [:done, :failed, :rolledback] ->
        {:stop, :normal, chain}

      _ ->
        {:noreply, chain}
    end
  end

  def handle_cast({:update, t_id, status}, chain) do
    {:noreply, update_in(chain.transactions, fn transactions ->
      Enum.map(transactions, fn
        %{id: ^t_id} = t -> %{t | state: status}
        t -> t
      end)
    end)}
  end

  def handle_cast({:update, t_id, cmd_id, status}, chain) do
    {:noreply, update_in(chain.transactions, fn transactions ->
      Enum.map(transactions, fn
        %{id: ^t_id} = t ->
          update_in(t.commands, fn commands ->
            Enum.map(commands, fn
              %{id: ^cmd_id} = cmd -> %{cmd | state: status}
              cmd -> cmd
            end)
          end)
        t -> t
      end)
    end)}
  end

  defp find_transaction(chain, id) do
    Enum.find(chain.transactions, nil, &(&1.id == id))
  end

  defp find_command(transaction, id) do
    Enum.find(transaction.commands, nil, &(&1.id == id))
  end
end
