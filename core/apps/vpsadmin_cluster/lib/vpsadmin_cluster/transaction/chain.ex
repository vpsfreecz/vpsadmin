defmodule VpsAdmin.Cluster.Transaction.Chain do
  @moduledoc """
  Transaction chains.

  Chain with a single transaction can be created using `single/2`, custom
  chains with `custom/1`.
  """

  alias VpsAdmin.Cluster
  alias VpsAdmin.Persistence
  alias VpsAdmin.Persistence.Schema

  def new do
    %Schema.Transaction.Chain{}
  end

  @doc "Create and persist a new chain"
  def create do
    new()
    |> Persistence.Transaction.Chain.create()
  end

  @doc "Stage chain with a single transaction"
  def stage_single(transaction_mod, opts \\ []) do
    stage_custom(fn chain -> append(chain, transaction_mod, opts) end)
  end

  @doc "Stage a custom chain built by `fun`"
  def stage_custom(fun) do
    Persistence.transaction(fn ->
      create()
      |> enter()
      |> fun.()
      |> leave()
    end)
  end

  @doc "Stage and execute chain with a single transaction"
  def single(transaction_mod, opts \\ []) do
    custom(fn chain -> append(chain, transaction_mod, opts) end)
  end

  @doc "Stage and execute a custom chain built by `fun`"
  def custom(fun) do
    Persistence.transaction(fn ->
      with {:ok, chain} <- stage_custom(fun),
           {:ok, chain} <- execute(chain) do
        chain
      else
        {:error, error} -> {:error, :error}
      end
    end)
  end

  @doc "Append a transaction to `chain`"
  def append(chain, transaction_mod, opts \\ []) do
    Cluster.Transaction.create(
      Cluster.Transaction.Context.new(chain),
      transaction_mod,
      opts
    )

    chain
  end

  @doc "Execute `chain`"
  def execute(chain) do
    chain = chain
      |> Schema.Transaction.Chain.changeset(%{state: :executing})
      |> Persistence.Transaction.Chain.update()

    chain = chain
      |> preload()
      |> set_nodes()
      |> set_transaction_nodes()

    raise "TODO"

    {:ok, chain}
  end

  @doc "Close `chain` on success or error"
  def close(chain, :ok) do
    Persistence.Repo.transaction(fn ->
      chain = Persistence.Transaction.Chain.preload(chain)

      for t <- chain.transactions, do: Cluster.Transaction.close(t, :ok)

      Persistence.ResourceLock.release(chain)

      chain
      |> Schema.Transaction.Chain.changeset(%{state: :done})
      |> Persistence.Transaction.Chain.update()
    end)
  end

  def close(chain, :error) do
    Persistence.Repo.transaction(fn ->
      chain = Persistence.Transaction.Chain.preload(chain)

      for t <- chain.transactions, do: Cluster.Transaction.close(t, :error)

      Persistence.ResourceLock.release(chain)

      chain
      |> Schema.Transaction.Chain.changeset(%{state: :failed})
      |> Persistence.Transaction.Chain.update()
    end)
  end

  @doc "Preload commonly required chain associations"
  def preload(chain, opts \\ []), do: Persistence.Transaction.Chain.preload(chain, opts)

  @doc """
  Put current process in the context of `chain.

  See `VpsAdmin.Persistence` and `VpsAdmin.Persistence.Transaction.processes`.
  """
  def enter(chain) do
    Persistence.Transaction.Processes.add(self(), chain.id)
    chain
  end

  @doc """
  Remove current process from the context of `chain.

  See `VpsAdmin.Persistence` and `VpsAdmin.Persistence.Transaction.processes`.
  """
  def leave(chain) do
    Persistence.Transaction.Processes.remove(self())
    chain
  end

  @doc """
  Set virtual field `nodes` with a list of nodes that are involved in `chain`.

  `nodes` is a list of tuples `{node_id, erlang node}`.
  """
  def set_nodes(chain) do
    update_in(chain.nodes, fn _ ->
      for n <- Persistence.Transaction.Chain.nodes(chain) do
        {n.id, Cluster.Node.erlang_node(n)}
      end
    end)
  end

  def set_transaction_nodes(chain) do
    update_in(chain.transactions, fn transactions ->
      for t <- transactions do
        Cluster.Transaction.set_nodes(t, chain.nodes)
      end
    end)
  end

  @doc """
  Returns a list of Erlang nodes involved in execution of `chain`.

  Requires chain nodes to be set by `set_nodes/1`.
  """
  def erlang_nodes(chain) do
    for {_id, enode} <- chain.nodes, do: enode
  end

  @doc """
  Returns a list of node IDs involved in execution of `chain`.

  Requires chain nodes to be set by `set_nodes/1`.
  """
  def node_ids(chain) do
    for {id, _enode} <- chain.nodes, do: id
  end
end
