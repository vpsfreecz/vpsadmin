class ToggleClusterResourceUse < ActiveRecord::Migration
  class ClusterResourceUse < ActiveRecord::Base ; end

  def up
    add_column :cluster_resource_uses, :enabled, :boolean, null: false, default: true

    ClusterResourceUse.where(confirmed: 2).update_all(confirmed: 1, enabled: false)
  end

  def down
    ClusterResourceUse.where(enabled: false).update_all(confirmed: 2)

    remove_column :cluster_resource_uses, :enabled
  end
end
