defmodule VpsAdmin.Persistence.Transaction.Confirmation do
  alias VpsAdmin.Persistence
  alias VpsAdmin.Persistence.Schema
  import Ecto.Query, only: [from: 2]

  def update(confirmation) do
    confirmation
    |> Persistence.Repo.update()
  end

  def for_transaction(transaction) do
    from(
      cnf in Schema.Transaction.Confirmation,
      join: cmd in assoc(cnf, :command),
      where: cmd.transaction_id == ^transaction.id,
      order_by: [cmd.id, cnf.id],
    ) |> Persistence.Repo.all()
  end

  def for_chain(chain) do
    from(
      cnf in Schema.Transaction.Confirmation,
      join: cmd in assoc(cnf, :command),
      join: tr in assoc(cmd, :transaction),
      where: tr.transaction_chain_id == ^chain.id,
      order_by: [tr.id, cmd.id, cnf.id],
    ) |> Persistence.Repo.all()
  end
end
