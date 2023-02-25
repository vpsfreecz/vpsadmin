class AddCgroupFlags < ActiveRecord::Migration[6.1]
  def change
    add_column :node_current_statuses, :cgroup_version, :integer, null: false, default: 1
    add_column :node_statuses, :cgroup_version, :integer, null: false, default: 1

    add_column :os_templates, :cgroup_version, :integer, null: false, default: 0
    add_index :os_templates, :cgroup_version

    add_column :vpses, :cgroup_version, :integer, null: false, default: 0
    add_index :vpses, :cgroup_version
  end
end
