defmodule VpsAdmin.Persistence.Schema.Node do
  use VpsAdmin.Persistence.Schema

  schema "nodes" do
    field :name, :string
    field :ip_addr, :string
    timestamps()

    belongs_to :location, Schema.Location

    confirmation_fields()
  end
end
