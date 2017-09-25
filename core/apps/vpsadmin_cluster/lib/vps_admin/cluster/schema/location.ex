defmodule VpsAdmin.Cluster.Schema.Location do
  use Ecto.Schema
  alias VpsAdmin.Cluster.Schema

  schema "locations" do
    field :label, :string
    field :domain, :string
    timestamps()

    has_many :nodes, Schema.Node
  end
end
