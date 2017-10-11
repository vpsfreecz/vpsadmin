defmodule VpsAdmin.Cluster.Transaction.Chain do
  @moduledoc """
  Behaviour for all transaction chains.

  Chain with a single transaction can be created using `single/2`, custom
  chains with `custom/1`.
  """

  alias VpsAdmin.Cluster
  alias VpsAdmin.Cluster.{Schema, Query}

  def new do
    %Schema.Transaction.Chain{}
  end

  def create do
    new()
    |> Cluster.Query.Transaction.Chain.create()
  end

  def single(transaction_mod, opts \\ []) do
    custom(fn chain -> append(chain, transaction_mod, opts) end)
  end

  def custom(fun) do
    Cluster.Repo.transaction(fn ->
      create()
      |> enter()
      |> fun.()
      |> leave()
      |> execute()
    end)
  end

  def append(chain, transaction_mod, opts \\ []) do
    Cluster.Transaction.create(
      Cluster.Transaction.Context.new(chain),
      transaction_mod,
      opts
    )

    chain
  end

  def execute(chain) do
    chain
    |> Schema.Transaction.Chain.changeset(%{state: :running})
    |> Query.Transaction.Chain.update()
  end

  def close(chain, :ok) do
    Cluster.Repo.transaction(fn ->
      chain = Query.Transaction.Chain.preload(chain)

      for t <- chain.transactions, do: Cluster.Transaction.close(t, :ok)

      Query.Transaction.Chain.release_locks(chain)

      chain
      |> Schema.Transaction.Chain.changeset(%{state: :done})
      |> Query.Transaction.Chain.update()
    end)
  end

  def close(chain, :error) do
    Cluster.Repo.transaction(fn ->
      chain = Cluster.Repo.preload(
        chain,
        transactions: [commands: :transaction_confirmations]
      )

      for t <- chain.transactions, do: Cluster.Transaction.close(t, :error)

      Query.Transaction.Chain.release_locks(chain)

      chain
      |> Schema.Transaction.Chain.changeset(%{state: :failed})
      |> Query.Transaction.Chain.update()
    end)
  end

  def preload(chain, opts \\ []), do: Query.Transaction.Chain.preload(chain, opts)

  def enter(chain) do
    Cluster.Transaction.Processes.add(self(), chain.id)
    chain
  end

  def leave(chain) do
    Cluster.Transaction.Processes.remove(self())
    chain
  end
end
