defmodule VpsAdmin.Persistence.InclusiveLock do
  alias VpsAdmin.Persistence

  def create(changeset) do
    Persistence.Repo.insert!(changeset)
  end
end
