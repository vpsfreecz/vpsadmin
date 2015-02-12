class Snapshot < ActiveRecord::Base
  belongs_to :dataset
  has_many :snapshot_in_pools
  has_many :snapshot_downloads
  belongs_to :snapshot_download

  include Confirmable

  def download
    TransactionChains::Dataset::Download.fire(self)
  end

  def mount
    sip = snapshot_in_pools.where.not(mount: nil).take
    sip && sip.mount
  end
end
