defmodule VpsAdmin.Persistence.Schema.Node do
  use VpsAdmin.Persistence.Schema

  schema "nodes" do
    field(:name, :string)
    field(:ip_addr, :string)
    field(:domain_name, :string, virtual: true)
    field(:fqdn, :string, virtual: true)
    belongs_to(:location, Schema.Location)
  end
end
