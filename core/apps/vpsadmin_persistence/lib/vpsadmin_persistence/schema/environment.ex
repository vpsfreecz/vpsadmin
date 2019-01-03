defmodule VpsAdmin.Persistence.Schema.Environment do
  use VpsAdmin.Persistence.Schema

  schema "environments" do
    field(:label, :string)
    field(:domain, :string)
    has_many(:locations, Schema.Location)
  end
end
