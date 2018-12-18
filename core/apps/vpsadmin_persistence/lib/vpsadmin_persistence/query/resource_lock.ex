defmodule VpsAdmin.Persistence.Query.ResourceLock do
  use VpsAdmin.Persistence.Query

  def release_by(type, id) do
    from(
      r in schema(),
      where: r.locked_by_id == ^id,
      where: r.locked_by_type == ^type
    ) |> repo().delete_all()
  end
end
