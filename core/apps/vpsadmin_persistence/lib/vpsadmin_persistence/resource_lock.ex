defmodule VpsAdmin.Persistence.ResourceLock do
  alias VpsAdmin.Persistence
  alias VpsAdmin.Persistence.Schema
  import Ecto.Query

  @doc "Return a tuple uniquelly identifying `struct`"
  @spec resource_ident(struct :: struct) :: {String.t, map}
  def resource_ident(struct) do
    name = resource_name(struct)
    id = resource_id(name, Map.from_struct(struct))
    {Atom.to_string(name), id}
  end

  def resource_name(struct) do
    struct.__struct__
  end

  def resource_id(schema, data) do
    for pk <- schema.__schema__(:primary_key), into: %{} do
      {pk, data[pk]}
    end
  end

  def create(changeset) do
    Persistence.Repo.insert!(changeset)
  end

  @doc "Upgrade an inclusive lock to an exclusive one"
  def upgrade(lock, chain) do
    from(
      inc in Schema.InclusiveLock,
      where: inc.resource == ^lock.resource,
      where: inc.resource_id == ^lock.resource_id,
      where: inc.transaction_chain_id == ^chain.id,
    ) |> Persistence.Repo.delete_all()

    Persistence.Repo.delete!(lock)

    %Schema.ResourceLock{}
    |> Map.put(:resource, lock.resource)
    |> Map.put(:resource_id, lock.resource_id)
    |> Map.put(:type, :exclusive)
    |> Map.put(:transaction_chain_id, lock.transaction_chain_id)
    |> Persistence.Repo.insert!()
  end

  @doc "Find an existing lock of `struct`"
  def find(struct, type) do
    {resource, id} = resource_ident(struct)

    from(
      lock in Schema.ResourceLock,
      where: lock.resource == ^resource,
      where: lock.resource_id == ^id,
      where: lock.type == ^type,
    ) |> Persistence.Repo.one()
  end

  @doc "Release all inclusive and exclusive locks held by `chain`"
  def release(chain) do
    from(lock in Schema.ResourceLock, where: lock.transaction_chain_id == ^chain.id)
    |> Persistence.Repo.delete_all()

    from(lock in Schema.InclusiveLock, where: lock.transaction_chain_id == ^chain.id)
    |> Persistence.Repo.delete_all()

    from(lock in Schema.ResourceLock, where: is_nil(fragment("""
        (SELECT resource FROM inclusive_locks WHERE resource = ? AND resource_id = ?)
      """, lock.resource, lock.resource_id))
    ) |> Persistence.Repo.delete_all()
  end
end
