class UnmanageVpsHostname < ActiveRecord::Migration
  def change
    add_column :vps, :manage_hostname, :boolean, null: false, default: true
  end
end
