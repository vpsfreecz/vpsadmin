defmodule VpsAdmin.Persistence.Node do
  import Ecto.Query
  alias VpsAdmin.Persistence
  alias VpsAdmin.Persistence.Schema

  def get_other_nodes(except_node_id) do
    from(n in Schema.Node, where: n.id != ^except_node_id)
    |> Persistence.Repo.all()
  end
end
