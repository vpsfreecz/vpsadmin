defmodule VpsAdmin.Cluster.Transaction.Custom do
  @moduledoc """
  Transaction whose body is passed as a function.

  When appending this transaction to a chain, its one parameter
  is a function that is given the `VpsAdmin.Cluster.Transaction.Context`
  as an argument. The function serves the same purpose as the `create/2`
  callback.
  """

  use VpsAdmin.Cluster.Transaction

  def label(), do: "Custom"

  @spec create(ctx :: Context.t, fun :: (Context.t -> Context.t)) :: Context.t
  def create(ctx, fun), do: fun.(ctx)
end
