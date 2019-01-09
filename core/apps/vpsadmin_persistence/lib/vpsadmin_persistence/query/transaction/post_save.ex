defmodule VpsAdmin.Persistence.Query.Transaction.PostSave do
  use VpsAdmin.Persistence.Query

  def snapshot_download(id, size, sha256sum) do
    from(
      dl in "snapshot_downloads",
      where: dl.id == ^id,
      update: [set: [size: ^size, sha256sum: ^sha256sum]]
    )
    |> repo().update_all([])
  end

  def group_snapshot(ids, name, created_at) do
    from(
      s in "snapshots",
      where: s.id in ^ids,
      update: [set: [name: ^name, created_at: ^created_at]]
    )
    |> repo().update_all([])
  end

  def snapshot(id, name, created_at) do
    group_snapshot([id], name, created_at)
  end
end
