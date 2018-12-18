defmodule VpsAdmin.Persistence.Query do
  defmacro __using__(_opts) do
    quote do
      alias VpsAdmin.Persistence
      alias VpsAdmin.Persistence.Schema
      alias VpsAdmin.Persistence.Query
      alias Ecto.Multi
      import Ecto.Query, only: [from: 2]

      @repo Persistence.Repo
      @schema Module.concat([Schema, __MODULE__ |> Module.split() |> List.last()])

      def repo, do: @repo
      def schema, do: @schema
    end
  end
end
