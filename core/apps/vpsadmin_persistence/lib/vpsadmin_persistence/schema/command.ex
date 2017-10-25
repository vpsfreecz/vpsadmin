defmodule VpsAdmin.Persistence.Schema.Command do
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

  schema "commands" do
    field :module, :string
    field :state, State
    field :params, :map, default: %{}
    field :output, :map
    timestamps()

    belongs_to :transaction, Schema.Transaction
    belongs_to :node, Schema.Node
    has_many :transaction_confirmations, Schema.Transaction.Confirmation
  end

  def changeset(cmd, params \\ %{}) do
    cmd
    |> Ecto.Changeset.change(params)
  end
end
