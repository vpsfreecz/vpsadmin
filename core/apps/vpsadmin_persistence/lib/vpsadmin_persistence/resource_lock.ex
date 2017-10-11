defmodule VpsAdmin.Persistence.ResourceLock do
  alias VpsAdmin.Persistence

  def create(changeset) do
    Persistence.Repo.insert!(changeset)
  end
end
