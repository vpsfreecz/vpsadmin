defmodule VpsAdmin.Persistence.Schema.Node do
  use VpsAdmin.Persistence.Schema

  schema "nodes" do
    field(:name, :string)
    field(:ip_addr, :string)
  end
end
