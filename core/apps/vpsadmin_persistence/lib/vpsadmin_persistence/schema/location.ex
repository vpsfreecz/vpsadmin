defmodule VpsAdmin.Persistence.Schema.Location do
  use VpsAdmin.Persistence.Schema

  schema "locations" do
    field(:label, :string)
    field(:domain, :string)
    belongs_to(:environment, Schema.Environment)
    has_many(:nodes, Schema.Node)
  end
end
