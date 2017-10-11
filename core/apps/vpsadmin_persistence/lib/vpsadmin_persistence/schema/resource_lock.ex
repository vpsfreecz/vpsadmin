defmodule VpsAdmin.Persistence.Schema.ResourceLock do
  use VpsAdmin.Persistence.Schema

  @primary_key false

  schema "resource_locks" do
    field :resource, :string, primary_key: true
    field :resource_id, :map, primary_key: true
    timestamps()

    belongs_to :transaction_chain, Schema.Transaction.Chain, foreign_key: :transaction_chain_id
  end

  def changeset(lock, params \\ %{}) do
    lock
    |> Ecto.Changeset.change(params)
    |> Ecto.Changeset.validate_required([:resource, :resource_id, :transaction_chain_id])
    |> Ecto.Changeset.unique_constraint(:resource, name: :resource_locks_pkey)
  end
end
