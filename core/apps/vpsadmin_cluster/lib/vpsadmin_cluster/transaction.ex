defmodule VpsAdmin.Cluster.Transaction do
  @moduledoc """
  Behaviour for transactions.

  Transactions are appended to chains using `VpsAdmin.Cluster.Transaction.Chain.append/3`.
  Transactions can use method from this module to add commands, include other
  transactions and track database changes.
  """

  alias VpsAdmin.Cluster
  alias VpsAdmin.Cluster.Transaction.Context
  alias VpsAdmin.Persistence
  alias VpsAdmin.Persistence.Schema

  @callback label() :: String.t
  @callback create(ctx :: Context.t, args :: any) :: Context.t

  defmacro __using__([]) do
    quote do
      @behaviour unquote(__MODULE__)
      alias VpsAdmin.Cluster
      alias VpsAdmin.Cluster.Transaction.Context
      alias VpsAdmin.Persistence
      alias VpsAdmin.Persistence.{Schema, Transaction, Command}
      import unquote(__MODULE__), only: [
        append: 2, append: 3, append: 4,
        include: 2, include: 3,
        lock: 2, lock: 3,
        run: 2,
      ]
      import Cluster.Transaction.Confirmation
    end
  end

  def new(ctx) do
    %Schema.Transaction{transaction_chain_id: ctx.chain.id}
  end

  def create(ctx, transaction_mod, opts) do
    tr = ctx
      |> new()
      |> Schema.Transaction.changeset(%{label: transaction_mod.label})
      |> Persistence.Transaction.create()

    ctx
    |> Cluster.Transaction.Context.transaction(tr)
    |> evaluate(transaction_mod, opts)
  end

  def evaluate(ctx, transaction_mod, opts) do
    transaction_mod.create(ctx, opts)
  end

  def close(trans, state) do
    for cmd <- trans.commands do
      for cnf <- cmd.transaction_confirmations do
        Cluster.Transaction.Confirmation.confirm(cnf, trans.transaction_chain_id, state)
      end
    end
  end

  def append(ctx, cmd_mod, opts \\ [], fun \\ nil) do
    ctx
    |> Cluster.Command.create(cmd_mod, opts, fun)
    |> Cluster.Command.finalize()
  end

  def include(ctx, transaction_mod, opts \\ []) do
    evaluate(ctx, transaction_mod, opts)
  end

  @spec lock(
    ctx :: map,
    schema_or_function :: (map | (map -> map)),
    :inclusive | :exclusive
  ) :: map
  def lock(ctx, schema_or_function, type \\ :exclusive)

  def lock(ctx, fun, type) when is_function(fun, 1), do: lock(ctx, fun.(ctx), type)

  def lock(ctx, schema, type), do: Cluster.ResourceLock.lock(ctx, schema, type)

  def run(ctx, fun) when is_function(fun, 0) do
    fun.()
    ctx
  end

  def run(ctx, fun) when is_function(fun, 1), do: fun.(ctx)

  def set_nodes(transaction, chain_node_tuples) do
    node_ids = for c <- transaction.commands, do: c.node_id
    node_tuples = Enum.reduce(
      chain_node_tuples,
      MapSet.new,
      fn {id, enode}, acc ->
        if id in node_ids do
          MapSet.put(acc, {id, enode})

        else
          acc
        end
      end
    )

    %{transaction | nodes: MapSet.to_list(node_tuples)}
  end

  @doc """
  Returns a list of Erlang nodes involved in execution of `transaction`.

  Requires chain nodes to be set by `set_nodes/2`.
  """
  def erlang_nodes(transaction) do
    for {_id, enode} <- transaction.nodes, do: enode
  end

  @doc """
  Returns a list of node IDs involved in execution of `transaction`.

  Requires chain nodes to be set by `set_nodes/2`.
  """
  def node_ids(transaction) do
    for {id, _enode} <- transaction.nodes, do: id
  end
end
