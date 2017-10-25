defmodule VpsAdmin.Persistence.Repo.Migrations.AddCommandsNode do
  use Ecto.Migration

  def change do
    alter table(:commands) do
      add :node_id, references(:nodes), null: false
    end
  end
end
