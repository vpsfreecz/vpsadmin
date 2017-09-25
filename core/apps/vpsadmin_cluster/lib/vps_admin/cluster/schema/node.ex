defmodule VpsAdmin.Cluster.Schema.Node do
  use Ecto.Schema
  alias VpsAdmin.Cluster.Schema

  schema "nodes" do
    field :name, :string
    field :ip_addr, :string
    timestamps()

    belongs_to :location, Schema.Location
  end
end
