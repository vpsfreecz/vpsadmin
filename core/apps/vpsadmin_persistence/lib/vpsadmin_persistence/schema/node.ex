defmodule VpsAdmin.Persistence.Schema.Node do
  use VpsAdmin.Persistence.Schema
  @behaviour Persistence.Lockable

  schema "nodes" do
    field :name, :string
    field :ip_addr, :string
    timestamps()

    belongs_to :location, Schema.Location

    confirmation_fields()
  end

  def lock_parent(node, _type) do
    {node.location, :inclusive}
  end
end
