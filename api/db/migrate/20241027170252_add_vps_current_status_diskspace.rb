class AddVpsCurrentStatusDiskspace < ActiveRecord::Migration[7.1]
  def change
    add_column :vps_current_statuses, :total_diskspace, :integer, null: true
    add_column :vps_current_statuses, :used_diskspace, :integer, null: true
    add_column :vps_current_statuses, :sum_used_diskspace, :integer, null: true

    add_column :vps_statuses, :total_diskspace, :integer, null: true
    add_column :vps_statuses, :used_diskspace, :integer, null: true
  end
end
