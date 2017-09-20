class AddPublicPrivateIpTransfers < ActiveRecord::Migration
  def up
    %i(ip_recent_traffics ip_traffics).each do |t|
      add_column t, :role, :integer, null: false, default: 0
      remove_index t, name: :transfers_unique
      add_index t, %i(ip_address_id user_id protocol role created_at), unique: true,
                name: :transfers_unique
    end

  end

  def down
    %i(ip_recent_traffics ip_traffics).each do |t|
      remove_column t, :role
      remove_index t, name: :transfers_unique
      add_index t, %i(ip_address_id user_id protocol created_at), unique: true,
                name: :transfers_unique
    end
  end
end
