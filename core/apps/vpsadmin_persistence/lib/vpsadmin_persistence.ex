defmodule VpsAdmin.Persistence do
  alias VpsAdmin.Persistence.{Repo, Schema, Transaction}
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
    |> Repo.one()
    |> handle_updated(chain)
  end

  def scoped_all(queryable, chain) do
    queryable
    |> scope(chain)
    |> Repo.all()
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
    Repo.preload(struct_or_list, associations)
  end

  def transaction(fun_or_multi, opts \\ []), do: Repo.transaction(fun_or_multi, opts)

  def handle_updated(nil, _chain), do: nil
  def handle_updated(struct_or_list, :confirmed), do: struct_or_list
  def handle_updated(struct_or_list, %{} = chain), do: handle_updated(struct_or_list, chain.id)
  def handle_updated(%{row_changes: nil} = struct, _chain), do: struct

  def handle_updated(%{row_changes: changes} = struct, chain_id) do
    Enum.reduce(
      changes,
      struct,
      fn {k, {chain, v}}, acc ->
        if chain == chain_id do
          Map.put(acc, k, v)

        else
          acc
        end
      end
    )
  end

  def handle_updated(items, chain_id) when is_list(items) do
    for v <- items, do: handle_updated(v, chain_id)
  end
end
