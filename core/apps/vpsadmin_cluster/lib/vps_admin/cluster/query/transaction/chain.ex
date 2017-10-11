defmodule VpsAdmin.Cluster.Query.Transaction.Chain do
  alias VpsAdmin.Cluster
  alias VpsAdmin.Cluster.Schema
  import Ecto.Query, only: [from: 2]

  def create(changeset), do: Cluster.Repo.insert!(changeset)

  def update(changeset), do: Cluster.Repo.update!(changeset)

  def locks(chain) do
    from(lock in Schema.ResourceLock, where: lock.transaction_chain_id == ^chain.id)
    |> Cluster.Repo.all()
  end

  def release_locks(chain) do
    from(lock in Schema.ResourceLock, where: lock.transaction_chain_id == ^chain.id)
    |> Cluster.Repo.delete_all()
  end

  def preload(chain, opts \\ []) do
    Cluster.Repo.preload(
      chain, [transactions: {
        from(t in Schema.Transaction, order_by: t.id),
        commands: {
          from(c in Schema.Command, order_by: c.id),
          transaction_confirmations: from(tc in Schema.Transaction.Confirmation, order_by: tc.id)
        }
      }], opts
    )
  end
end
