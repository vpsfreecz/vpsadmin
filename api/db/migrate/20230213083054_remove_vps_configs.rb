class RemoveVpsConfigs < ActiveRecord::Migration[6.1]
  def up
    drop_table :environment_config_chains
    drop_table :vps_has_configs
    drop_table :vps_configs
  end
end
