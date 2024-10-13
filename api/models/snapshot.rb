require_relative 'confirmable'
require_relative 'lockable'

class Snapshot < ApplicationRecord
  belongs_to :dataset
  has_many :snapshot_in_pools
  has_many :snapshot_downloads
  belongs_to :snapshot_download

  include Confirmable
  include Lockable

  def mount
    sip = snapshot_in_pools.where.not(mount: nil).take
    sip && sip.mount
  end

  def export
    ::Export.joins(snapshot_in_pool_clone: :snapshot_in_pool).where(
      snapshot_in_pools: { snapshot_id: id }
    ).take
  end
end
