defmodule VpsAdmin.Cluster.Migration do
  defmacro __using__(_opts) do
    quote do
      use Ecto.Migration
      import unquote(__MODULE__)
    end
  end

  defmacro confirmation_columns() do
    quote do
      add :row_state, :integer, null: false, default: 1
      add :row_changes, :map
      add :row_changed_by_id, references(:transaction_chains)
    end
  end
end
