defmodule VpsAdmin.Cluster.Transaction.Context do
  @moduledoc """
  Struct carrying context information for chains, transactions and commands.

  Transaction must know what chain it is part of, commands must know what
  transaction are they in, confirmations are also dependent on transaction.
  This struct provides a way to access current chain, transaction or
  command.

  Resource locks are added to the context using `lock/2`, checking for
  existing locks is done with `locked?/2`. All chain locks are stored
  there.

  Context can also be used to pass data from transaction to commands
  and vice-versa using `put/3`. The data can then be accessed through
  struct key `data`.
  """

  defstruct chain: nil, transaction: nil, command: nil, locks: [], data: %{}

  @type t :: struct

  @doc "Create an empty context for `chain`"
  def new(chain), do: %__MODULE__{chain: chain}

  @doc "Scope context `ctx` to transaction `tr`"
  def transaction(ctx, tr), do: %{ctx | transaction: tr, command: nil}

  @doc "Scope context `ctx` to command `cmd`"
  def command(ctx, cmd), do: %{ctx | command: cmd}

  @doc """
  Add lock

  Note that the lock must be created using `VpsAdmin.Cluster.Transaction.lock/2`
  beforehand.
  """
  def lock(ctx, lock), do: %{ctx | locks: [lock | ctx.locks]}

  @doc "Check if a specific resource is already locked"
  def locked?(ctx, lock, type) do
    case find_lock(ctx, lock) do
      false ->
        false
      existing_lock ->
        case existing_lock.type do
          ^type -> true
          :inclusive -> {:upgrade, existing_lock}
          :exclusive -> true
        end
    end
  end

  @doc "Store custom data in struct field `data` with key `k` and value `v`"
  def put(ctx, k, v), do: update_in(ctx.data, fn data -> Map.put(data, k, v) end)

  defp find_lock(ctx, lock) do
    Enum.find(ctx.locks, false, fn v ->
      v.resource == lock.resource && v.resource_id == lock.resource_id
    end)
  end
end
