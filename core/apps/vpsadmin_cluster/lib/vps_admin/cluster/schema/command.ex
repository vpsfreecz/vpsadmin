defmodule VpsAdmin.Cluster.Schema.Command do
  use VpsAdmin.Cluster.Schema

  import EctoEnum, only: [defenum: 2]
  defenum State, queued: 0, executing: 1, done: 2, failed: 3

  schema "commands" do
    field :module, :string
    field :state, State
    field :params, :map, default: %{}
    field :output, :map
    timestamps()

    belongs_to :transaction, Schema.Transaction
    has_many :transaction_confirmations, Schema.Transaction.Confirmation
  end
end
