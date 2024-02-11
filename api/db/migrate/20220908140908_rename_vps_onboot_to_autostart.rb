class RenameVpsOnbootToAutostart < ActiveRecord::Migration[6.1]
  class Vps < ActiveRecord::Base
    has_one :vps_current_status
  end

  class VpsCurrentStatus < ActiveRecord::Base; end

  def change
    remove_column :locations, :vps_onboot, :boolean, null: false, default: true
    remove_column :vpses, :onboot, :boolean, null: false, default: true
    add_column :vpses, :autostart_enable, :boolean, null: false, default: false

    reversible do |dir|
      dir.up do
        Vps.all.includes(:vps_current_status).each do |vps|
          vps.update!(autostart_enable: true) if vps.vps_current_status && vps.vps_current_status.is_running
        end
      end
    end
  end
end
