defmodule VpsAdmin.Cluster.Schema.Node do
  use VpsAdmin.Cluster.Schema

  schema "nodes" do
    field :name, :string
    field :ip_addr, :string
    timestamps()

    belongs_to :location, Schema.Location

    confirmation_fields()
  end
end
