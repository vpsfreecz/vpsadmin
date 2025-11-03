class AddVpsQemuGuestAgent < ActiveRecord::Migration[7.2]
  def change
    add_column :vps_current_statuses, :qemu_guest_agent, :boolean, null: false, default: false
    add_column :vps_statuses, :qemu_guest_agent, :boolean, null: false, default: false
  end
end
