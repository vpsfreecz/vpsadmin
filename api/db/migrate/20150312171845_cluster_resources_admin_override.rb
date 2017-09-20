class ClusterResourcesAdminOverride < ActiveRecord::Migration
  def change
    add_column :cluster_resource_uses, :admin_lock_type, :integer, null: false, default: 0
    add_column :cluster_resource_uses, :admin_limit,     :integer, null: true
  end
end
