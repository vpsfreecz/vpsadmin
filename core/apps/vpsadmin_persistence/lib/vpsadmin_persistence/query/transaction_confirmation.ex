defmodule VpsAdmin.Persistence.Query.TransactionConfirmation do
  use VpsAdmin.Persistence.Query

  def list(chain_id) do
    from(
      c in schema(),
      join: t in assoc(c, :transaction),
      select: {c, t.status},
      where: t.transaction_chain_id == ^chain_id,
      where: c.done == ^false,
      order_by: [asc: c.id]
    )
    |> repo().all()
  end

  def run(chain_id) do
    for {c, status} <- list(chain_id) do
      do_confirm(c, status)
    end

    mark_as_done(chain_id)
  end

  def mark_as_done(chain_id) do
    from(
      c in schema(),
      join: t in assoc(c, :transaction),
      where: t.transaction_chain_id == ^chain_id,
      where: c.done == ^false,
      update: [set: [done: true]]
    )
    |> repo().update_all([])
  end

  defp do_confirm(%{confirm_type: :create} = confirmation, :done) do
    pks_cond = row_pks(confirmation.row_pks)

    from(
      t in confirmation.table_name,
      where: ^pks_cond,
      update: [set: [confirmed: 1]]
    )
    |> repo().update_all([])
  end

  defp do_confirm(%{confirm_type: :create} = confirmation, :failed) do
    pks_cond = row_pks(confirmation.row_pks)

    from(
      t in confirmation.table_name,
      where: ^pks_cond
    )
    |> repo().delete_all()
  end

  defp do_confirm(%{confirm_type: :just_create}, :done) do
    :ok
  end

  defp do_confirm(%{confirm_type: :just_create} = confirmation, :failed) do
    pks_cond = row_pks(confirmation.row_pks)

    from(
      t in confirmation.table_name,
      where: ^pks_cond
    )
    |> repo().delete_all()
  end

  defp do_confirm(%{confirm_type: :edit_before}, :done) do
    :ok
  end

  defp do_confirm(%{confirm_type: :edit_before} = confirmation, :failed) do
    pks_cond = row_pks(confirmation.row_pks)

    from(
      t in confirmation.table_name,
      where: ^pks_cond,
      update: [set: ^changes(confirmation.attr_changes)]
    )
    |> repo().update_all([])
  end

  defp do_confirm(%{confirm_type: :edit_after} = confirmation, :done) do
    pks_cond = row_pks(confirmation.row_pks)

    from(
      t in confirmation.table_name,
      where: ^pks_cond,
      update: [set: ^changes(confirmation.attr_changes)]
    )
    |> repo().update_all([])
  end

  defp do_confirm(%{confirm_type: :edit_after}, :failed) do
    :ok
  end

  defp do_confirm(%{confirm_type: :destroy} = confirmation, :done) do
    pks_cond = row_pks(confirmation.row_pks)

    from(
      t in confirmation.table_name,
      where: ^pks_cond
    )
    |> repo().delete_all()
  end

  defp do_confirm(%{confirm_type: :destroy} = confirmation, :failed) do
    pks_cond = row_pks(confirmation.row_pks)

    from(
      t in confirmation.table_name,
      where: ^pks_cond,
      update: [set: [confirmed: 1]]
    )
    |> repo().update_all([])
  end

  defp do_confirm(%{confirm_type: :just_destroy} = confirmation, :done) do
    pks_cond = row_pks(confirmation.row_pks)

    from(
      t in confirmation.table_name,
      where: ^pks_cond
    )
    |> repo().delete_all()
  end

  defp do_confirm(%{confirm_type: :just_destroy}, :failed) do
    :ok
  end

  defp do_confirm(%{confirm_type: :increment} = confirmation, :done) do
    pks_cond = row_pks(confirmation.row_pks)
    attr = confirmation.attr_changes

    from(
      t in confirmation.table_name,
      where: ^pks_cond,
      update: [inc: [{^String.to_atom(attr), 1}]]
    )
    |> repo().update_all([])
  end

  defp do_confirm(%{confirm_type: :increment}, :failed) do
    :ok
  end

  defp do_confirm(%{confirm_type: :decrement} = confirmation, :done) do
    pks_cond = row_pks(confirmation.row_pks)
    attr = confirmation.attr_changes

    from(
      t in confirmation.table_name,
      where: ^pks_cond,
      update: [inc: [{^String.to_atom(attr), -1}]]
    )
    |> repo().update_all([])
  end

  defp do_confirm(%{confirm_type: :decrement}, :failed) do
    :ok
  end

  defp row_pks(map), do: atomize(map)

  defp changes(map), do: atomize(map)

  defp atomize(map) when is_map(map), do: Enum.map(map, fn {k, v} -> {atomize(k), v} end)
  defp atomize(":" <> s) when is_binary(s), do: String.to_atom(s)
  defp atomize(s) when is_binary(s), do: String.to_atom(s)
end
