class RefactorVpsConfigs < ActiveRecord::Migration
  def change
    rename_table :config, :vps_configs
    rename_table :vps_has_config, :vps_has_configs
    rename_column :vps_has_configs, :config_id, :vps_config_id
  end
end
