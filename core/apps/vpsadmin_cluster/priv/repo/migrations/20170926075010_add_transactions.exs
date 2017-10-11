defmodule VpsAdmin.Cluster.Repo.Migrations.AddTransactions do
  use VpsAdmin.Cluster.Migration

  def change do
    create table(:transaction_chains) do
      add :label, :string
      add :state, :integer, null: false, default: 0
      add :progress, :integer, null: false, default: 0
      timestamps()
    end

    create index(:transaction_chains, :state)

    create table(:transactions) do
      add :transaction_chain_id, references(:transaction_chains), null: false
      add :label, :string, null: false
      add :state, :integer, null: false, default: 0
      add :progress, :integer, null: false, default: 0
      timestamps()
    end

    create index(:transactions, :transaction_chain_id)
    create index(:transactions, :state)

    create table(:commands) do
      add :transaction_id, references(:transactions), null: false
      add :module, :string, null: false
      add :state, :integer, null: false, default: 0
      add :params, :map, null: false
      add :output, :map
      timestamps()
    end

    create index(:commands, :transaction_id)
    create index(:commands, :module)
    create index(:commands, :state)

    create table(:transaction_confirmations) do
      add :command_id, references(:commands), null: false
      add :type, :integer, null: false
      add :state, :integer, null: false, default: 0
      add :table, :string, null: false
      add :row_pks, :map, null: false
      add :changes, :map
      timestamps()
    end

    create index(:transaction_confirmations, :command_id)

    create table(:resource_locks, primary_key: false) do
      add :resource, :string, null: false, primary_key: true
      add :resource_id, :map, null: false, primary_key: true
      add :transaction_chain_id, references(:transaction_chains), null: false
      timestamps()
    end

    alter table(:locations) do
      confirmation_columns()
    end

    alter table(:nodes) do
      confirmation_columns()
    end
  end
end
