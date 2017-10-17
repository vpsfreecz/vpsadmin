defmodule VpsAdmin.Persistence.Schema.InclusiveLock do
  use VpsAdmin.Persistence.Schema

  @primary_key false

  schema "inclusive_locks" do
    field :resource, :string, primary_key: true
    field :resource_id, :map, primary_key: true
    timestamps()

    belongs_to :transaction_chain, Schema.Transaction.Chain,
      foreign_key: :transaction_chain_id,
      primary_key: true
  end

  def changeset(lock, params \\ %{}) do
    lock
    |> Ecto.Changeset.change(params)
    |> Ecto.Changeset.validate_required([:resource, :resource_id, :transaction_chain_id])
    |> Ecto.Changeset.foreign_key_constraint(:resource, name: :inclusive_lock_resource_fkey)
    |> Ecto.Changeset.foreign_key_constraint(:transaction_chain_id)
  end
end
