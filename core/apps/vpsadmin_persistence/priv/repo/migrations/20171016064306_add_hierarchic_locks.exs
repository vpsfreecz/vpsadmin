defmodule VpsAdmin.Persistence.Repo.Migrations.AddHierarchicLocks do
  use Ecto.Migration

  def up do
    alter table(:resource_locks) do
      add :type, :integer, null: false
      modify :transaction_chain_id, :integer, null: true
    end

    create table(:inclusive_locks, primary_key: false) do
      add :resource, :string, null: false, primary_key: true
      add :resource_id, :map, null: false, primary_key: true
      add :transaction_chain_id, references(:transaction_chains), null: false, primary_key: true
      timestamps()
    end

    execute """
      ALTER TABLE inclusive_locks
      ADD CONSTRAINT inclusive_locks_resource_fkey
      FOREIGN KEY(resource, resource_id)
      REFERENCES resource_locks(resource, resource_id)
    """
  end

  def down do
    drop table(:inclusive_locks)

    alter table(:resource_locks) do
      remove :type
      modify :transaction_chain_id, :integer, null: false
    end
  end
end
