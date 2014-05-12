class VpsMount < ActiveRecord::Base
  self.table_name = 'vps_mount'

  belongs_to :storage_export
  belongs_to :node, foreign_key: :server_id
  belongs_to :vps

  has_paper_trail

  validates :vps_id, :dst, :mount_opts, :umount_opts, :mount_type, :mode,
            presence: true
  validates :vps_id, numericality: {
      only_integer: true
  }
  validates :mount_type, inclusion: {
      in: %w(bind nfs),
      message: '%{value} is not a valid mount type'
  }
  validates :mode, inclusion: {
      in: %w(ro rw),
      message: '%{value} is not a valid mount mode'
  }

  def self.default_mounts
    self.where(default: true)
  end
end
