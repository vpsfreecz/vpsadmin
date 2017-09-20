class VoluntaryNodeAttributes < ActiveRecord::Migration
  def change
    change_column_null :servers, :max_vps, true

    reversible do |dir|
      dir.up do
        change_column :servers, :ve_private, :string, limit: 255, null: true,
                      default: '/vz/private/%{veid}/private'
      end
      
      dir.down do
        change_column :servers, :ve_private, :string, limit: 255, null: false,
                      default: '/vz/private/%veid%'
      end
    end
  end
end
