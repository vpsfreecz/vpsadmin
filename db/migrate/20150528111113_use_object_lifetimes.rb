class UseObjectLifetimes < ActiveRecord::Migration
  class ObjectState < ActiveRecord::Base
    enum state: %i(active suspended soft_delete hard_delete deleted)
  end

  class User < ActiveRecord::Base
    self.table_name = 'members'
    self.primary_key = 'm_id'
  end

  class Vps < ActiveRecord::Base
    self.table_name = 'vps'
    self.primary_key = 'vps_id'
  end

  class Dataset < ActiveRecord::Base ; end

  class SnapshotDownload < ActiveRecord::Base ; end

  def change
    add_column :members, :object_state, :integer, null: false
    add_column :members, :expiration_date, :datetime, null: true

    add_column :vps, :object_state, :integer, null: false
    add_column :vps, :expiration_date, :datetime, null: true

    add_column :datasets, :object_state, :integer, null: false
    add_column :datasets, :expiration_date, :datetime, null: true

    add_column :snapshot_downloads, :object_state, :integer, null: false
    add_column :snapshot_downloads, :expiration_date, :datetime, null: true

    reversible do |dir|
      dir.up do
        User.all.each do |u|
          ObjectState.create!(
              class_name: 'User',
              row_id: u.id,
              state: 0,
              expiration_date: nil,
              user_id: nil,
              created_at: Time.at(u.m_created.to_i)
          )

          ObjectState.create!(
              class_name: 'User',
              row_id: u.id,
              state: {
                  'suspended' => 1,
                  'deleted' => 2
              }[u.m_state],
              expiration_date: nil,
              user_id: nil,
              reason: u.m_suspend_reason
          ) if u.m_state != 'active'

          u.update!(
              object_state: {
                  'active' => 0,
                  'suspended' => 1,
                  'deleted' => 2
              }[u.m_state] || 0
          )
        end

        Vps.all.each do |vps|
          expiration = vps.vps_expiration ? Time.at(vps.vps_expiration.to_i) : nil

          ObjectState.create!(
              class_name: 'Vps',
              row_id: vps.id,
              state: 0,
              expiration_date: expiration,
              user_id: nil,
              created_at: Time.at(vps.vps_created.to_i)
          )

          ObjectState.create!(
              class_name: 'Vps',
              row_id: vps.id,
              state: 2,
              expiration_date: nil,
              user_id: nil,
              created_at: Time.at(vps.vps_deleted.to_i)
          ) if vps.vps_deleted

          vps.update!(
              object_state: vps.vps_deleted ? 2 : 0,
              expiration_date: expiration
          )
        end

        Dataset.all.each do |ds|
          ObjectState.create!(
              class_name: 'Dataset',
              row_id: ds.id,
              state: 0,
              expiration_date: nil,
              user_id: nil,
              created_at: Time.now
          )
        end

        SnapshotDownload.all.each do |s|
          ObjectState.create!(
              class_name: 'SnapshotDownload',
              row_id: s.id,
              state: 0,
              expiration_date: nil,
              user_id: nil,
              created_at: s.created_at
          )
        end
      end

      dir.down do
        User.all.each do |u|
          last = ObjectState.where(
              class_name: 'User',
              row_id: u.id
          ).order('created_at DESC').take!

          u.update!(
              m_deleted: %w(soft_delete hard_delete).include?(last.state) ? last.created_at.to_i : nil,
              m_state: {
                  active: 'active',
                  suspended: 'suspended',
                  soft_delete: 'deleted',
                  hard_delete: 'deleted'
              }[last.state.to_sym],
              m_suspend_reason: last.reason
          )
        end

        Vps.all.each do |vps|
          last = ObjectState.where(
              class_name: 'Vps',
              row_id: vps.id
          ).order('created_at DESC').take!

          vps.update!(
              vps_expiration: last.expiration_date.to_i,
              vps_deleted: %w(soft_delete hard_delete).include?(last.state) ? last.created_at.to_i : nil,
          )
        end

        ObjectState.delete_all
      end
    end

    remove_column :members, :m_deleted, :integer
    # NOTE: the original type was enum(active, suspended, deleted)
    remove_column :members, :m_state, :string, null: false, default: 'active'
    remove_column :members, :m_suspend_reason, :string, limit: 100

    remove_column :vps, :vps_expiration, :integer
    remove_column :vps, :vps_deleted, :integer
  end
end
