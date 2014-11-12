class AddEnvironmentConfig < ActiveRecord::Migration
  def change
    add_column :environments, :can_create_vps, :boolean, null: false, default: false
    add_column :environments, :can_destroy_vps, :boolean, null: false, default: false
    add_column :environments, :vps_lifetime, :integer, null: false, default: 0
    add_column :environments, :max_vps_count, :integer, null: false, default: 1

    create_table :environment_config_chains do |t|
      t.references :environment,   null: false
      t.references :vps_config,    null: false
      t.integer    :cfg_order,     null: false
    end

    add_index :environment_config_chains, [:environment_id, :vps_config_id], unique: true,
              name: :environment_config_chains_unique

    remove_column :locations, :location_type, "enum('production', 'playground')", null: false

    create_table :environment_user_configs do |t|
      t.references :environment
      t.references :user
      t.boolean    :can_create_vps,   null: false, default: false
      t.boolean    :can_destroy_vps,  null: false, default: false
      t.boolean    :vps_lifetime,     null: false, default: 0
      t.integer    :max_vps_count,    null: false, default: 1
    end

    add_index :environment_user_configs, [:environment_id, :user_id], unique: true,
              name: :environment_user_configs_unique
  end
end
