defmodule VpsAdmin.Persistence.Schema.ResourceLock do
  use VpsAdmin.Persistence.Schema

  schema "resource_locks" do
    field(:resource, :string)
    field(:row_id, :integer)
    field(:locked_by_id, :integer)
    field(:locked_by_type, :string)

    timestamps(
      type: :utc_datetime,
      inserted_at: :created_at,
      updated_at: :updated_at
    )
  end
end
