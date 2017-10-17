defmodule VpsAdmin.Cluster.ResourceLock do
  @moduledoc """
  Hierarchic resource lock management.

  Resource locks are used to limit access to particular resources to transaction
  chains, so that two excluding chains cannot work on the same data at the same
  time.

  There are two types of locks: inclusive and exclusive. An inclusive lock
  can be thought of as a read-only lock. Multiple chains can hold this lock
  on the same resource. Exclusive lock can be held only by one chain per
  resource. If a resource is locked inclusively, exclusive lock cannot be
  acquired. Similarly, if a resource is locked exclusively, no inclusive lock
  can be acquired either.

  Locks are hierarchic, it means that we're not locking just the resource we're
  working with, but we're locking all its parents too. For example, if
  a transaction manipulates a VPS, it locks it together with the node the VPS
  is on, its location and the entire cluster. Lock for the VPS is exclusive,
  parent locks are inclusive. This allows us to safely manipulate resources
  that may have child resources.

  Lockable resources (structs) need to implement the
  `VpsAdmin.Persistence.Lockable` behaviour.
  """

  alias VpsAdmin.Cluster.Transaction
  alias VpsAdmin.Persistence
  alias VpsAdmin.Persistence.{Lockable, Schema}

  @doc "Create a new lock struct for `struct`"
  def new(ctx, struct, type) do
    {resource, id} = Persistence.ResourceLock.resource_ident(struct)

    %{
      resource: resource,
      resource_id: id,
      transaction_chain_id: ctx.chain.id,
      type: type,
    }
  end

  @doc "Create and persist a new lock of `struct` described by `params`"
  def create(struct, %{type: :inclusive} = params) do
    {:ok, lock} = Persistence.transaction(fn ->
      lock = case Persistence.ResourceLock.find(struct, :inclusive) do
        nil ->
          %Schema.ResourceLock{}
            |> Schema.ResourceLock.changeset(%{params | transaction_chain_id: nil})
            |> Persistence.ResourceLock.create()

        lock ->
          lock
      end

      %Schema.InclusiveLock{}
      |> Schema.InclusiveLock.changeset(%{
           resource: lock.resource,
           resource_id: lock.resource_id,
           transaction_chain_id: params.transaction_chain_id,
         })
      |> Persistence.InclusiveLock.create()

      lock
    end)

    lock
  end

  def create(_struct, %{type: :exclusive} = params) do
    %Schema.ResourceLock{}
    |> Schema.ResourceLock.changeset(params)
    |> Persistence.ResourceLock.create()
  end

  @doc "Lock `struct` and all its parents"
  def lock(ctx, struct, type) do
    Enum.reduce(
      Lockable.get_entities(struct, type),
      ctx,
      &lock_ent(&1, &2)
    )
  end

  defp lock_ent({struct, type}, ctx) do
    params = new(ctx, struct, type)

    case Transaction.Context.locked?(ctx, params, type) do
      true ->
        ctx

      false ->
        lock = create(struct, params)
        Transaction.Context.lock(ctx, lock)

      {:upgrade, lock} ->
        lock = Persistence.ResourceLock.upgrade(lock, ctx.chain)
        Transaction.Context.lock(ctx, lock)
    end
  end
end
