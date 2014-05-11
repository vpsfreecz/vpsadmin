class StorageExport < ActiveRecord::Base
  self.table_name = 'storage_export'

  belongs_to :user, foreign_key: :member_id
  belongs_to :storage_root, foreign_key: :root_id

  has_paper_trail

  validates :member_id, :root_id, :dataset, :path, :quota, :data_type,
            presence: true
  validates :member_id, :root_id, :quota, :used, :avail, numericality: {
      only_integer: true
  }
  validates :default, inclusion: {
      in: %w(no member vps),
      message: '%{value} is not a valid value'
  }
  validates :data_type, inclusion: {
      in: %w(data backup),
      message: '%{value} is not a valid data type'
  }
end
