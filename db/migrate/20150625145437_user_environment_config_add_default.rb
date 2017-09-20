class UserEnvironmentConfigAddDefault < ActiveRecord::Migration
  def change
    add_column :environment_user_configs, :default, :boolean, null: false, default: true
  end
end

