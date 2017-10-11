defmodule VpsAdmin.Persistence.Schema.Transaction.Confirmation do
  @moduledoc """
  Schema for transaction confirmations

  This module provides changeset functions for operations on confirmable
  table rows:

   - `insert_changeset/2`
   - `update_changeset/2`
   - `delete_changeset/3`
  """

  use Ecto.Schema
  alias VpsAdmin.Persistence.Schema

  import EctoEnum, only: [defenum: 2]
  defenum Type, insert: 0, delete: 1, update: 2
  defenum State, unconfirmed: 0, confirmed: 1, discarded: 2
  defenum RowState, confirmed: 0, new: 1, updated: 2, deleted: 3

  defmodule RowChanges do
    @behaviour Ecto.Type

    def type, do: :map

    def cast(nil), do: {:ok, nil}
    def cast(%{} = map), do: {:ok, map}
    def cast(_), do: :error

    def dump(nil), do: {:ok, nil}
    def dump(%{} = map) do
      {:ok, (for {k, {chain, v}} <- map, into: %{}, do: {k, [chain, v]})}
    end
    def dump(_), do: :error

    def load(nil), do: {:ok, nil}
    def load(%{} = map) do
      {:ok, for {k, [chain, v]} <- map, into: %{} do
        {String.to_atom(k), {chain, v}}
      end}
    end
    def load(_), do: :error
  end

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
      field :row_changes, Schema.Transaction.Confirmation.RowChanges
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
  def update_changeset(ctx, schema_or_changeset, chain_id, new_changes \\ %{}) do
    changeset = Ecto.Changeset.change(schema_or_changeset)

    changeset
    |> do_update_changeset(
         Ecto.Changeset.get_field(changeset, :row_state),
         chain_id,
         new_changes
       )
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

  defp do_update_changeset(changeset, :new, chain_id, new_changes) do
    changes = Ecto.Changeset.get_field(changeset, :row_changes)
    merge_changes(changeset, chain_id, changes, new_changes)
  end

  defp do_update_changeset(changeset, :deleted, _chain_id, _new_changes) do
    Ecto.Changeset.add_error(
      changeset,
      :row_state,
      "cannot update row that is marked for deletion",
      Ecto.Changeset.apply_changes(changeset)
    )
  end

  defp do_update_changeset(changeset, _state, chain_id, new_changes) do
    changes = Ecto.Changeset.get_field(changeset, :row_changes)

    changeset
    |> merge_changes(chain_id, changes, new_changes)
    |> Ecto.Changeset.change(%{row_state: :updated})
  end

  defp merge_changes(changeset, chain_id, nil, new) do
    Ecto.Changeset.change(changeset, %{row_changes: Enum.reduce(
      new,
      %{},
      fn {k, v}, acc -> Map.put(acc, k, {chain_id, v}) end
    )})
  end

  defp merge_changes(changeset, chain_id, old, new) do
    changes = Enum.reduce_while(
      new,
      old,
      fn {k, v}, acc ->
        case acc[k] do
          nil ->
            {:cont, Map.put(acc, k, {chain_id, v})}

          {^chain_id, _value} ->
            {:cont, Map.put(acc, k, {chain_id, v})}

          {other_chain, _value} ->
            {:halt, {other_chain, k}}
        end
      end
    )

    case changes do
      %{} ->
        Ecto.Changeset.change(changeset, %{row_changes: changes})

      {chain, key} ->
        Ecto.Changeset.add_error(
          changeset,
          :row_changes,
          "column '#{key}' is already being changed by chain ##{chain}"
        )
    end
  end

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
