defmodule VpsAdmin.Persistence.Transaction do
  alias VpsAdmin.Persistence
  alias VpsAdmin.Persistence.Schema

  import Ecto.Query, only: [from: 2]

  def create(changeset) do
    Persistence.Repo.insert!(changeset)
  end

  def update_state(trans, changes) do
    from(
      t in Schema.Transaction,
      where: t.id == ^trans.id,
    ) |> Persistence.Repo.update_all(set: Enum.into(changes, []))
  end
end
