class StorageRoot < ActiveRecord::Base
  self.table_name = 'storage_root'

  belongs_to :node

  validates :node_id, :label, :root_dataset, :root_path, :storage_layout,
            :user_mount, :quota, :share_options, presence: true
  validates :storage_layout, inclusion: {
      in: %w(per_member per_vps),
      message: '%{value} is not a valid layout'
  }
  validates :user_mount, inclusion: {
      in: %w(none ro rw),
      message: '%{value} is not a valid user mount access'
  }
end
