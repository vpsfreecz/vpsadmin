class AddLifetimesToMounts < ActiveRecord::Migration
  class Mount < ActiveRecord::Base ; end

  def change
    add_column :mounts, :object_state, :integer, null: true
    add_column :mounts, :expiration_date, :datetime, null: true

    reversible do |dir|
      dir.up do
        # Put all mounts to active state
        Mount.all.update_all(object_state: 0)

        # Set expiration_date of snapshot mounts to 3 days in the future
        Mount.where.not(snapshot_in_pool_id: nil).update_all(
            expiration_date: Time.now + 3 * 24 * 60 * 60
        )
      end
    end
    
    change_column_null :mounts, :object_state, false
    add_timestamps :mounts
  end
end
