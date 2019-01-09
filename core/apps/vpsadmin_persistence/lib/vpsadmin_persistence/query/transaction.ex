defmodule VpsAdmin.Persistence.Query.Transaction do
  use VpsAdmin.Persistence.Query

  def list(chain_id) do
    from(
      t in schema(),
      where: t.transaction_chain_id == ^chain_id,
      order_by: [asc: t.id],
      preload: [node: ^Query.Node.preload()]
    )
    |> repo().all()
  end

  def started(trans_id) do
    from(
      t in schema(),
      where: t.id == ^trans_id,
      update: [set: [started_at: ^DateTime.utc_now()]]
    )
    |> repo().update_all([])
  end

  def finished(trans_id, done, status, output) do
    from(
      t in schema(),
      where: t.id == ^trans_id,
      update: [
        set: [
          done: ^done,
          status: ^status,
          output: ^output,
          finished_at: ^DateTime.utc_now()
        ]
      ]
    )
    |> repo().update_all([])
  end

  def clear_input(trans_id) do
    from(
      t in schema(),
      where: t.id == ^trans_id,
      update: [set: [input: ^%{}]]
    )
    |> repo().update_all([])
  end
end
