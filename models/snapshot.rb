class Snapshot < ActiveRecord::Base
  belongs_to :dataset
  has_many :snapshot_in_pools
  has_many :snapshot_downloads
  belongs_to :snapshot_download

  include Confirmable
  include Lockable
  
  def destroy
    TransactionChains::Snapshot::Destroy.fire(self)
  end

  def download(format)
    TransactionChains::Dataset::Download.fire(self, format)
  end

  def mount
    sip = snapshot_in_pools.where.not(mount: nil).take
    sip && sip.mount
  end
end
