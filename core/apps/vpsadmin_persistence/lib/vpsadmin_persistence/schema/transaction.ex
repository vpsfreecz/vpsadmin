defmodule VpsAdmin.Persistence.Schema.Transaction do
  use VpsAdmin.Persistence.Schema

  import EctoEnum, only: [defenum: 2]
  defenum State, queued: 0, executing: 1, done: 2, failed: 3

  schema "transactions" do
    field :label, :string
    field :state, State
    field :progress, :integer
    timestamps()

    belongs_to :transaction_chain, Schema.Transaction.Chain
    has_many :commands, Schema.Command
  end

  def changeset(trans, params) do
    trans
    |> Ecto.Changeset.cast(params, [:label])
    |> Ecto.Changeset.validate_required([:label])
  end
end
