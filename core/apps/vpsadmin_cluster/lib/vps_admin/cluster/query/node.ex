defmodule VpsAdmin.Cluster.Query.Node do
  import Ecto.Query
  alias VpsAdmin.Cluster
  alias VpsAdmin.Cluster.Schema

  def get_other_nodes() do
    id = Cluster.Node.self_id()

    from(n in Schema.Node, where: n.id != ^id)
    |> Cluster.Repo.all()
  end
end
