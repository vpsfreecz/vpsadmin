defmodule VpsAdmin.Cluster.Transaction.Confirmation do
  @moduledoc """
  Confirm/discard database changes based on transaction execution.

  Transactions changing systems using commands, these changes must be reflected
  in the database. Since commands are not guaranteed to success, the database
  changes must be revertable. There can be three types of database changes:
  insert, update and delete. All tables that can contain confirmable data must
  include several columns, see `VpsAdmin.Persistence.Migration.confirmation_columns/0`
  and `VpsAdmin.Persistence.Schema.Transaction.Confirmation/confirmation_fields/0`.

  Changed rows are marked so that you can query for confirmed or latest data,
  based on your context, see `VpsAdmin.Persistence`. Changes are not permanent
  until the transaction chain is closed. Then the changes are either confirmed
  or discarded. There is also a protection on insert/delete operations, that
  only one transaction chain can change these rows. Table row can be updated
  multiple times by different chains at once, if there's no conflict between
  the changes.

  Transactions use functions `insert/2`, `delete/2` and `change/3` to register
  database changes. These functions must be called from a function that is
  passed as the last argument to `VpsAdmin.Cluster.Transaction.append/4`.
  Database changes must be backed by transaction commands, otherwise they can
  be confirmed immediately and there's no need for this system.

  Function `confirm/1` is used to confirm actual changes when the chain is being
  closed.
  """

  alias VpsAdmin.Cluster.Transaction.Context
  alias VpsAdmin.Persistence
  alias VpsAdmin.Persistence.Schema
  require Ecto.Query

  @schema Schema.Transaction.Confirmation

  @doc """
  Confirm creation of a new table row.

  The new row can be given as a schema or changeset struct. The schema can be
  already saved in the database, but does not have to be.
  """
  @spec insert(ctx :: Context.t, schema_or_changeset :: struct) :: {Context.t, struct}
  def insert(ctx, %Ecto.Changeset{} = changeset) do
    changeset = @schema.insert_changeset(ctx, changeset)

    row = if Ecto.get_meta(changeset.data, :state) == :built do
      Persistence.Repo.insert!(changeset)
    else
      Persistence.Repo.update!(changeset)
    end

    {update_in(
      ctx.command.transaction_confirmations,
      &[make_confirmation(:insert, row) | &1]
    ), row}
  end

  def insert(ctx, schema) do
    insert(ctx, Ecto.Changeset.change(schema))
  end

  @doc "Confirm deletion of an existing table row."
  @spec delete(ctx :: Context.t, schema_or_changeset :: struct) :: {Context.t, struct}
  def delete(ctx, %Ecto.Changeset{} = changeset) do
    row = ctx
      |> @schema.delete_changeset(changeset)
      |> Persistence.Repo.update!()

    {update_in(
      ctx.command.transaction_confirmations,
      &[make_confirmation(:delete, row) | &1]
    ), row}
  end

  def delete(ctx, schema) do
    delete(ctx, Ecto.Changeset.change(schema))
  end

  @doc "Confirm update of an existing table row."
  @spec change(
    ctx :: Context.t,
    schema_or_changeset :: struct,
    changes :: map
  ) :: {Context.t, struct}
  def change(ctx, %Ecto.Changeset{} = changeset, changes) do
    changeset = @schema.update_changeset(ctx, changeset, ctx.chain.id, changes)

    row = Persistence.Repo.update!(changeset)

    {update_in(
      ctx.command.transaction_confirmations,
      &[make_confirmation(:update, row, changes) | &1]
    ), changeset |> Ecto.Changeset.change(changes) |> Ecto.Changeset.apply_changes()}
  end

  def change(ctx, schema, changes) do
    change(ctx, Ecto.Changeset.change(schema), changes)
  end

  def confirm(cnf, chain_id, :ok) do
    pks = for {k,v} <- cnf.row_pks, do: {String.to_atom(k), v}
    states = Schema.Transaction.Confirmation.RowState.__enum_map__()

    case cnf.type do
      :insert ->
        Ecto.Query.from(cnf.table, where: ^pks)
        |> Persistence.Repo.update_all(set: [row_state: states[:confirmed]])

      :delete ->
        Ecto.Query.from(cnf.table, where: ^pks)
        |> Persistence.Repo.delete_all()

      :update ->
        changes = for {k,v} <- cnf.changes, do: {String.to_atom(k), v}

        q = Ecto.Query.from(cnf.table, where: ^pks)
        row = Persistence.Repo.one(Ecto.Query.from(q, select: [:row_changes]))
        {state, row_changes} = clear_changes(row[:row_changes], chain_id)

        Persistence.Repo.update_all(q, set: changes ++ [
          row_state: states[state],
          row_changes: row_changes,
        ])
    end

    {:ok, _} = cnf
      |> Schema.Transaction.Confirmation.close_changeset(%{state: :confirmed})
      |> Persistence.Transaction.Confirmation.update()
  end

  def confirm(cnf, chain_id, :error) do
    pks = for {k,v} <- cnf.row_pks, do: {String.to_atom(k), v}
    states = Schema.Transaction.Confirmation.RowState.__enum_map__()

    case cnf.type do
      :insert ->
        Ecto.Query.from(cnf.table, where: ^pks)
        |> Persistence.Repo.delete_all()

      :delete ->
        Ecto.Query.from(cnf.table, where: ^pks)
        |> Persistence.Repo.update_all(set: [row_state: states[:confirmed]])

      :update ->
        q = Ecto.Query.from(cnf.table, where: ^pks)
        row = Persistence.Repo.one(Ecto.Query.from(q, select: [:row_changes]))
        {state, row_changes} = clear_changes(row[:row_changes], chain_id)

        Persistence.Repo.update_all(q, set: [
          row_state: states[state],
          row_changes: row_changes,
        ])
    end

    {:ok, _} = cnf
      |> Schema.Transaction.Confirmation.close_changeset(%{state: :discarded})
      |> Persistence.Transaction.Confirmation.update()
  end

  defp make_confirmation(type, data) when type in ~w(insert delete)a do
    schema = data.__struct__
    map = Map.from_struct(data)

    %@schema{
      type: type,
      table: schema.__schema__(:source),
      row_pks: primary_keys(schema, map),
    }
  end

  defp make_confirmation(:update, data, changes) do
    schema = data.__struct__
    map = Map.from_struct(data)

    %@schema{
      type: :update,
      table: schema.__schema__(:source),
      row_pks: primary_keys(schema, map),
      changes: changes,
    }
  end

  defp primary_keys(schema, data) do
    for pk <- schema.__schema__(:primary_key), into: %{} do
      {pk, data[pk]}
    end
  end

  defp clear_changes(changes, chain_id) do
    changes = for {k, [chain, v]} <- changes, chain != chain_id, into: %{} do
      {k, [chain, v]}
    end

    if map_size(changes) > 0 do
      {:updated, changes}
    else
      {:confirmed, nil}
    end
  end
end
