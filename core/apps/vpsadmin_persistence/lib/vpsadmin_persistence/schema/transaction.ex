defmodule VpsAdmin.Persistence.Schema.Transaction do
  use VpsAdmin.Persistence.Schema

  import EctoEnum, only: [defenum: 2]
  defenum State,
    queued: 0,
    executing: 1,
    done: 2,
    failed: 3,
    rollingback: 4,
    rolledback: 5,
    fatal: 6

  schema "transactions" do
    field :label, :string
    field :state, State
    field :progress, :integer
    timestamps()

    belongs_to :transaction_chain, Schema.Transaction.Chain
    has_many :commands, Schema.Command

    field :nodes, :any, virtual: true, default: nil
  end

  def changeset(trans, params) do
    trans
    |> Ecto.Changeset.cast(params, [:label])
    |> Ecto.Changeset.validate_required([:label])
  end

  def update_changeset(trans, params) do
    trans
    |> Ecto.Changeset.change(params)
  end
end
