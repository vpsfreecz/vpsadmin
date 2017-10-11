defmodule VpsAdmin.Cluster.Transaction.Chain do
  @moduledoc """
  Behaviour for all transaction chains.

  Chain with a single transaction can be created using `single/2`, custom
  chains with `custom/1`.
  """

  alias VpsAdmin.Cluster
  alias VpsAdmin.Persistence
  alias VpsAdmin.Persistence.Schema

  def new do
    %Schema.Transaction.Chain{}
  end

  def create do
    new()
    |> Persistence.Transaction.Chain.create()
  end

  def single(transaction_mod, opts \\ []) do
    custom(fn chain -> append(chain, transaction_mod, opts) end)
  end

  def custom(fun) do
    Persistence.Repo.transaction(fn ->
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
    |> Persistence.Transaction.Chain.update()
  end

  def close(chain, :ok) do
    Persistence.Repo.transaction(fn ->
      chain = Persistence.Transaction.Chain.preload(chain)

      for t <- chain.transactions, do: Cluster.Transaction.close(t, :ok)

      Persistence.Transaction.Chain.release_locks(chain)

      chain
      |> Schema.Transaction.Chain.changeset(%{state: :done})
      |> Persistence.Transaction.Chain.update()
    end)
  end

  def close(chain, :error) do
    Persistence.Repo.transaction(fn ->
      chain = Persistence.Transaction.Chain.preload(chain)

      for t <- chain.transactions, do: Cluster.Transaction.close(t, :error)

      Persistence.Transaction.Chain.release_locks(chain)

      chain
      |> Schema.Transaction.Chain.changeset(%{state: :failed})
      |> Persistence.Transaction.Chain.update()
    end)
  end

  def preload(chain, opts \\ []), do: Persistence.Transaction.Chain.preload(chain, opts)

  def enter(chain) do
    Persistence.Transaction.Processes.add(self(), chain.id)
    chain
  end

  def leave(chain) do
    Persistence.Transaction.Processes.remove(self())
    chain
  end
end
