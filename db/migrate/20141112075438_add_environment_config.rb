class AddEnvironmentConfig < ActiveRecord::Migration
  def change
    add_column :environments, :can_create_vps, :boolean, null: false, default: false
    add_column :environments, :can_destroy_vps, :boolean, null: false, default: false
    add_column :environments, :vps_lifetime, :integer, null: false, default: 0

    create_table :environment_config_chains do |t|
      t.references :environment,   null: false
      t.references :vps_config,    null: false
      t.integer    :cfg_order,     null: false
    end

    add_index :environment_config_chains, [:environment_id, :vps_config_id], unique: true,
              name: :environment_config_chains_unique
  end
end
