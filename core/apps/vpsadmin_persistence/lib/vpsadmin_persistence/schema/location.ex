defmodule VpsAdmin.Persistence.Schema.Location do
  use VpsAdmin.Persistence.Schema
  @behaviour Persistence.Lockable

  schema "locations" do
    field :label, :string
    field :domain, :string
    timestamps()

    has_many :nodes, Schema.Node

    confirmation_fields()
  end

  def lock_parent(_location, _type) do
    {%Schema.Cluster{}, :inclusive}
  end
end
