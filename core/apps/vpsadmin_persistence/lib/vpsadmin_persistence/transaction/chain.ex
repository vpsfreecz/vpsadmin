defmodule VpsAdmin.Persistence.Transaction.Chain do
  alias VpsAdmin.Persistence
  alias VpsAdmin.Persistence.Schema
  import Ecto.Query

  def create(changeset), do: Persistence.Repo.insert!(changeset)

  def update(changeset), do: Persistence.Repo.update!(changeset)

  def update_state(chain, changes) do
    from(
      chain in Schema.Transaction.Chain,
      where: chain.id == ^chain.id,
    ) |> Persistence.Repo.update_all(set: Enum.into(changes, []))
  end

  def locks(chain) do
    from(
      lock in Schema.ResourceLock,
      left_join: inc in Schema.InclusiveLock,
      on: inc.resource == lock.resource and inc.resource_id == lock.resource_id,
      where: lock.transaction_chain_id == ^chain.id or inc.transaction_chain_id == ^chain.id,
      group_by: [
        lock.resource, lock.resource_id, lock.type, lock.transaction_chain_id,
        inc.transaction_chain_id,
      ],
      select: struct(lock, [:resource, :resource_id, :type, :transaction_chain_id]),
    ) |> Persistence.Repo.all()
  end

  def preload(chain, opts \\ []) do
    Persistence.Repo.preload(
      chain, [transactions: {
        from(t in Schema.Transaction, order_by: t.id),
        commands: {
          from(c in Schema.Command, order_by: c.id),
          transaction_confirmations: from(tc in Schema.Transaction.Confirmation, order_by: tc.id)
        }
      }], opts
    )
  end

  def nodes(chain) do
    from(
      tr in Schema.Transaction,
      join: cmd in assoc(tr, :commands),
      join: n in assoc(cmd, :node),
      where: tr.transaction_chain_id == ^chain.id,
      group_by: [n.id, n.name, n.ip_addr, n.location_id],
      select: struct(n, [:id, :name, :ip_addr, :location_id]),
    ) |> Persistence.Repo.all()
  end
end
