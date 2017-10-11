defmodule VpsAdmin.Cluster.Schema.Transaction.Confirmation do
  @moduledoc """
  Schema for transaction confirmations

  This module provides changeset functions for operations on confirmable
  table rows:

   - `insert_changeset/2`
   - `update_changeset/2`
   - `delete_changeset/3`
  """

  use Ecto.Schema
  alias VpsAdmin.Cluster.Schema

  import EctoEnum, only: [defenum: 2]
  defenum Type, insert: 0, delete: 1, update: 2
  defenum State, unconfirmed: 0, confirmed: 1, discarded: 2
  defenum RowState, confirmed: 0, new: 1, updated: 2, deleted: 3

  schema "transaction_confirmations" do
    field :type, Type
    field :state, State
    field :table, :string
    field :row_pks, :map
    field :changes, :map
    timestamps()

    belongs_to :command, Schema.Command
  end

  @doc "Adds schema fields required for row confirmation"
  defmacro confirmation_fields() do
    quote do
      field :row_state, Schema.Transaction.Confirmation.RowState
      field :row_changes, :map
      belongs_to :transaction_chain, Schema.Transaction.Chain, foreign_key: :row_changed_by_id
    end
  end

  @doc "Changeset for inserting new unconfirmed rows"
  def insert_changeset(ctx, schema_or_changeset) do
    schema_or_changeset
    |> Ecto.Changeset.change(%{row_state: :new})
    |> lock_row(ctx)
  end

  @doc "Changeset for updating confirmable rows"
  def update_changeset(ctx, schema_or_changeset, new_changes \\ %{}) do
    changeset = Ecto.Changeset.change(schema_or_changeset)

    changeset
    |> do_update_changeset(
         Ecto.Changeset.get_field(changeset, :row_state),
         new_changes
       )
    |> lock_row(ctx)
  end

  @doc "Changeset for deleting confirmable rows"
  def delete_changeset(ctx, schema_or_changeset) do
    schema_or_changeset
    |> Ecto.Changeset.change(%{row_state: :deleted})
    |> lock_row(ctx)
  end

  @doc "Changeset for closing of transaction confirmation itself"
  def close_changeset(confirmation, params \\ %{}) do
    confirmation
    |> Ecto.Changeset.change(params)
  end

  defp do_update_changeset(changeset, :new, new_changes) do
    changes = Ecto.Changeset.get_field(changeset, :row_changes)
    Ecto.Changeset.change(changeset, %{
      row_changes: merge_changes(changes, new_changes),
    })
  end

  defp do_update_changeset(changeset, :deleted, _new_changes) do
    Ecto.Changeset.add_error(
      changeset,
      :row_state,
      "cannot update row that is marked for deletion",
      Ecto.Changeset.apply_changes(changeset)
    )
  end

  defp do_update_changeset(changeset, _state, new_changes) do
    changes = Ecto.Changeset.get_field(changeset, :row_changes)
    Ecto.Changeset.change(changeset, %{
      row_changes: merge_changes(changes, new_changes),
      row_state: :updated,
    })
  end

  defp merge_changes(nil, new), do: new
  defp merge_changes(old, new), do: Map.merge(old, new)

  defp lock_row(changeset, ctx) do
    case Ecto.Changeset.get_field(changeset, :row_changed_by_id) do
      nil ->
        Ecto.Changeset.change(changeset, %{row_changed_by_id: ctx.chain.id})

      id when is_integer(id) ->
        if id == ctx.chain.id do
          changeset

        else
          Ecto.Changeset.add_error(
            changeset,
            :row_changed_by_id,
            "this row is already being manipulated by chain ##{id}",
            changeset.data
          )
        end
    end
  end
end
