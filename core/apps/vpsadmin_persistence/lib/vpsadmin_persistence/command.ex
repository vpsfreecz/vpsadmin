defmodule VpsAdmin.Persistence.Command do
  alias VpsAdmin.Persistence
  alias VpsAdmin.Persistence.Schema

  import Ecto.Query, only: [from: 2]

  def create(changeset) do
    Persistence.Repo.insert!(changeset)
  end

  def update_state(cmd, changes) do
    from(
      c in Schema.Command,
      where: c.id == ^cmd.id,
    ) |> Persistence.Repo.update_all(set: Enum.into(changes, []))
  end
end
