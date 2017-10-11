defmodule VpsAdmin.Cluster.Transaction do
  @moduledoc """
  Behaviour for transactions.

  Transactions are appended to chains using `VpsAdmin.Cluster.Transaction.Chain.append/3`.
  Transactions can use method from this module to add commands, include other
  transactions and track database changes.
  """

  alias VpsAdmin.Cluster
  alias VpsAdmin.Persistence
  alias VpsAdmin.Persistence.Schema

  @callback label() :: String.t
  @callback create(ctx :: map, args :: any) :: map

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
        lock: 2,
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

  @spec lock(ctx :: map, schema_or_function :: (map | (map -> map))) :: map
  def lock(ctx, fun) when is_function(fun, 1), do: lock(ctx, fun.(ctx))

  def lock(ctx, schema) do
    params = Cluster.ResourceLock.new(ctx, schema)

    if Cluster.Transaction.Context.locked?(ctx, params) do
      ctx

    else
      lock = %Schema.ResourceLock{}
        |> Schema.ResourceLock.changeset(params)
        |> Persistence.ResourceLock.create()

      Cluster.Transaction.Context.lock(ctx, lock)
    end
  end

  def run(ctx, fun) when is_function(fun, 0) do
    fun.()
    ctx
  end

  def run(ctx, fun) when is_function(fun, 1), do: fun.(ctx)
end
