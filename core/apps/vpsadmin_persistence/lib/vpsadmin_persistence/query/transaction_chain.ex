defmodule VpsAdmin.Persistence.Query.TransactionChain do
  use VpsAdmin.Persistence.Query

  def get(chain_id) do
    from(
      c in schema(),
      where: c.id == ^chain_id
    ) |> repo().one()
  end

  def get_open_ids do
    from(
      c in schema(),
      select: c.id,
      where: c.state in ^[:executing, :rollingback],
      order_by: [asc: c.id]
    ) |> repo().all()
  end

  def get_open_ids_since(chain_id) do
    from(
      c in schema(),
      select: c.id,
      where: c.state in ^[:executing, :rollingback],
      where: c.id > ^chain_id,
      order_by: [asc: c.id]
    ) |> repo().all()
  end

  def progress(chain_id, :executed, :done) do
    from(
      c in schema(),
      where: c.id == ^chain_id,
      update: [inc: [progress: 1]]
    ) |> repo().update_all([])
  end

  def progress(chain_id, :rolledback, :done) do
    from(
      c in schema(),
      where: c.id == ^chain_id,
      update: [inc: [progress: -1]]
    ) |> repo().update_all([])
  end

  def progress(_chain_id, _done, _status), do: nil

  def close(chain_id, state) do
    Multi.new
    |> Multi.update_all(
         :close,
         from(c in schema(), where: c.id == ^chain_id),
         set: [state: state]
       )
    |> Multi.run(
         :confirmations,
         fn _repo, changes ->
           Query.TransactionConfirmation.run(chain_id)
           {:ok, changes}
         end
       )
    |> Multi.run(
         :locks,
         fn _repo, changes ->
           Query.ResourceLock.release_by("TransactionChain", chain_id)
           {:ok, changes}
         end
       )
    |> repo().transaction()
  end

  def abort(chain_id) do
    from(
      c in schema(),
      where: c.id == ^chain_id,
      update: [set: [state: ^:aborted]]
    ) |> repo().update_all([])
  end
end
