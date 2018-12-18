defmodule VpsAdmin.Persistence.Query.Transaction do
  use VpsAdmin.Persistence.Query

  def started(trans_id) do
    from(
      t in schema(),
      where: t.id == ^trans_id,
      update: [set: [started_at: ^DateTime.utc_now()]]
    ) |> repo().update_all([])
  end

  def finished(trans_id, done, status, output) do
    from(
      t in schema(),
      where: t.id == ^trans_id,
      update: [set: [
        done: ^done,
        status: ^status,
        output: ^output,
        finished_at: ^DateTime.utc_now()
      ]]
    ) |> repo().update_all([])
  end
end
