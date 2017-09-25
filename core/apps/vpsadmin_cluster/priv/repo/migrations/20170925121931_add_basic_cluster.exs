defmodule VpsAdmin.Cluster.Repo.Migrations.AddBasicCluster do
  use Ecto.Migration

  def change do
    create table(:locations) do
      add :label, :string, null: false
      add :domain, :string, null: false
      timestamps()
    end

    create table(:nodes) do
      add :name, :string, null: false
      add :location_id, references(:locations), null: false
      add :ip_addr, :string, null: false, limit: 40
      timestamps()
    end

    create unique_index(:nodes, ~w(name location_id)a, name: :nodes_name_unique)
  end
end
