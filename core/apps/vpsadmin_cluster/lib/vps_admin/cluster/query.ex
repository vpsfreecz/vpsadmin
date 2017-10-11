defmodule VpsAdmin.Cluster.Query do
  alias VpsAdmin.Cluster
  alias VpsAdmin.Cluster.{Schema, Transaction}
  import Ecto.Query, only: [from: 2]

  def scope(queryable, v) when v in [nil, :confirmed] do
    states = Schema.Transaction.Confirmation.RowState.__enum_map__

    from(q in queryable, where: q.row_state in ^[
      states[:confirmed],
      states[:updated],
      states[:deleted],
    ])
  end

  def scope(queryable, %{} = chain), do: scope(queryable, chain.id)

  def scope(queryable, chain_id) when is_integer(chain_id) do
    states = Schema.Transaction.Confirmation.RowState.__enum_map__

    from(
      q in queryable,
      where: (q.row_state in ^[
        states[:confirmed],
        states[:updated],
      ]) or (q.row_state == ^states[:new] and q.row_changed_by_id == ^chain_id)
    )
  end

  def scoped_get(queryable, id, chain) do
    from(q in queryable, where: q.id == ^id)
    |> scoped_one(chain)
  end

  def scoped_one(queryable, chain) do
    queryable
    |> scope(chain)
    |> Cluster.Repo.one()
    |> handle_updated(chain)
  end

  def scoped_all(queryable, chain) do
    queryable
    |> scope(chain)
    |> Cluster.Repo.all()
    |> handle_updated(chain)
  end

  def get(queryable, id) do
    scoped_get(queryable, id, Transaction.Processes.chain_id)
  end

  def one(queryable) do
    scoped_one(queryable, Transaction.Processes.chain_id)
  end

  def all(queryable) do
    scoped_all(queryable, Transaction.Processes.chain_id)
  end

  def preload(struct_or_list, associations) do
    Cluster.Repo.preload(struct_or_list, associations)
  end

  def handle_updated(nil, _chain), do: nil
  def handle_updated(struct_or_list, :confirmed), do: struct_or_list
  def handle_updated(struct_or_list, %{} = chain), do: handle_updated(struct_or_list, chain.id)
  def handle_updated(%{row_changes: nil} = struct, chain), do: struct

  def handle_updated(%{row_changes: changes} = struct, chain_id) do
    if chain_id == struct.row_changed_by_id do
      apply_changes(struct, changes)

    else
      struct
    end
  end

  def handle_updated(items, chain_id) when is_list(items) do
    for v <- items, do: handle_updated(v, chain_id)
  end

  defp apply_changes(struct, changes) do
    Enum.reduce(
      changes,
      struct,
      fn {k, v}, acc ->
        Map.put(acc, String.to_atom(k), v)
      end
    )
  end
end
