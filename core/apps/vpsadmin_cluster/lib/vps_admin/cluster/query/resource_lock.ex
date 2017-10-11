defmodule VpsAdmin.Cluster.Query.ResourceLock do
  alias VpsAdmin.Cluster

  def create(changeset) do
    Cluster.Repo.insert!(changeset)
  end
end
