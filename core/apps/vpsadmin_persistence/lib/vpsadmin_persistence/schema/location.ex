defmodule VpsAdmin.Persistence.Schema.Location do
  use VpsAdmin.Persistence.Schema

  schema "locations" do
    field :label, :string
    field :domain, :string
    timestamps()

    has_many :nodes, Schema.Node

    confirmation_fields()
  end
end
