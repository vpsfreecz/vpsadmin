defmodule VpsAdmin.Persistence.Schema.Cluster do
  @moduledoc "An abstract schema representing the entire vpsAdmin cluster"

  use VpsAdmin.Persistence.Schema
  @behaviour Persistence.Lockable

  @primary_key false

  schema "abstract cluster" do
  end

  def lock_parent(_cluster, _type), do: nil
end
