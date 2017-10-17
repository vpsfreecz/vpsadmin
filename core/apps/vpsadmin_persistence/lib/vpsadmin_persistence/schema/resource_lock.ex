defmodule VpsAdmin.Persistence.Schema.ResourceLock do
  use VpsAdmin.Persistence.Schema

  import EctoEnum, only: [defenum: 2]
  defenum Type, inclusive: 0, exclusive: 1

  @primary_key false

  schema "resource_locks" do
    field :resource, :string, primary_key: true
    field :resource_id, :map, primary_key: true
    field :type, Type
    timestamps()

    belongs_to :transaction_chain, Schema.Transaction.Chain, foreign_key: :transaction_chain_id
  end

  def changeset(lock, params \\ %{}) do
    lock
    |> Ecto.Changeset.change(params)
    |> Ecto.Changeset.validate_required([:resource, :resource_id, :type])
    |> changeset_for_type(params.type)
    |> Ecto.Changeset.unique_constraint(:resource, name: :resource_locks_pkey)
  end

  def changeset_for_type(changeset, :inclusive), do: changeset
  def changeset_for_type(changeset, :exclusive) do
    changeset
    |> Ecto.Changeset.validate_required([:transaction_chain_id])
  end
end
