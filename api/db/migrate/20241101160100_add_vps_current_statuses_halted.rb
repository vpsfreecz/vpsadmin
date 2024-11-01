class AddVpsCurrentStatusesHalted < ActiveRecord::Migration[7.1]
  def change
    add_column :vps_current_statuses, :halted, :boolean, default: false, null: false
  end
end
