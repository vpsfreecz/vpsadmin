defmodule VpsAdmin.Persistence.Schema do
  defmacro __using__(_opts) do
    quote do
      use Ecto.Schema
      alias VpsAdmin.Persistence
      alias Persistence.Schema
      import Schema.Transaction.Confirmation, only: [confirmation_fields: 0]
    end
  end
end
