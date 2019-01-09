defmodule VpsAdmin.Persistence.Query.PortReservation do
  use VpsAdmin.Persistence.Query

  def release_by(id) do
    from(
      r in schema(),
      where: r.transaction_chain_id == ^id,
      update: [set: [transaction_chain_id: ^nil]]
    )
    |> repo().update_all([])
  end
end
