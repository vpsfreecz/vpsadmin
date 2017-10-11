defmodule VpsAdmin.Cluster.Query.Command do
  alias VpsAdmin.Cluster

  def create(changeset) do
    Cluster.Repo.insert!(changeset)
  end
end
