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

  def download(format, from_snapshot = nil)
    if format == :incremental_stream
      TransactionChains::Dataset::IncrementalDownload.fire(self, format, from_snapshot)

    else
      TransactionChains::Dataset::FullDownload.fire(self, format)
    end
  end

  def mount
    sip = snapshot_in_pools.where.not(mount: nil).take
    sip && sip.mount
  end
end
