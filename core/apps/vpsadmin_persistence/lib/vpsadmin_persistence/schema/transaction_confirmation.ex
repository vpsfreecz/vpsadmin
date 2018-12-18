defmodule VpsAdmin.Persistence.Schema.TransactionConfirmation do
  use VpsAdmin.Persistence.Schema

  defmodule YamlType do
    @behaviour Ecto.Type

    def type, do: :string

    def cast(v) when is_map(v), do: {:ok, v}

    def load(v), do: YamlElixir.read_from_string(v)

    def dump(v), do: {:ok, Jason.encode!(v)}
  end

  defenum(
    ConfirmType,
    Enum.with_index(~w(
      create just_create
      edit_before edit_after
      destroy just_destroy
      decrement increment
    )a)
  )

  schema "transaction_confirmations" do
    field(:class_name, :string)
    field(:table_name, :string)
    field(:row_pks, YamlType)
    field(:attr_changes, YamlType)
    field(:confirm_type, ConfirmType)
    field(:done, :boolean)

    timestamps(
      type: :utc_datetime,
      inserted_at: :created_at,
      updated_at: :updated_at
    )

    belongs_to(:transaction, Schema.Transaction)
  end
end
