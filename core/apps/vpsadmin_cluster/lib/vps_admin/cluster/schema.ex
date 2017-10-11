defmodule VpsAdmin.Cluster.Schema do
  defmacro __using__(_opts) do
    quote do
      use Ecto.Schema
      alias VpsAdmin.Cluster
      alias Cluster.Schema
      import Schema.Transaction.Confirmation, only: [confirmation_fields: 0]
    end
  end
end
