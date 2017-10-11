defmodule VpsAdmin.Cluster.Query.Transaction do
  alias VpsAdmin.Cluster

  def create(changeset) do
    Cluster.Repo.insert!(changeset)
  end
end
