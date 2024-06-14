class AddUserDevicesLastSeenAt < ActiveRecord::Migration[7.1]
  def change
    add_column :user_devices, :last_seen_at, :datetime, null: true

    reversible do |dir|
      dir.up do
        ActiveRecord::Base.connection.execute('UPDATE user_devices SET last_seen_at = updated_at')
      end
    end

    change_column_null :user_devices, :last_seen_at, false
  end
end
