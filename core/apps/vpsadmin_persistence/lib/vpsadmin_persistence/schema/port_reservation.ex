defmodule VpsAdmin.Persistence.Schema.PortReservation do
  use VpsAdmin.Persistence.Schema

  schema "port_reservations" do
    field(:addr, :string)
    field(:port, :integer)
    belongs_to(:node, Schema.Node)
    belongs_to(:transaction_chain, Schema.TransactionChain)
  end
end
