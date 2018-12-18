defmodule VpsAdmin.Persistence.Schema do
  defmacro __using__(_opts) do
    quote do
      use Ecto.Schema
      import Ecto.Changeset
      import EctoEnum
      alias VpsAdmin.Persistence
      alias VpsAdmin.Persistence.Schema
    end
  end
end
