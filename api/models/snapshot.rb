require_relative 'confirmable'
require_relative 'lockable'

class Snapshot < ApplicationRecord
  belongs_to :dataset
  has_many :snapshot_in_pools
  has_many :snapshot_downloads
  belongs_to :snapshot_download

  include Confirmable
  include Lockable

  def destroy
    TransactionChains::Snapshot::Destroy.fire(self)
  end

  # @param opts [Hash]
  # @option opts [Symbol] format
  # @option opts [Snapshot] from_snapshot
  # @option opts [Boolean] send_mail
  def download(opts)
    if opts[:format] == :incremental_stream
      TransactionChains::Dataset::IncrementalDownload.fire(self, opts)

    else
      TransactionChains::Dataset::FullDownload.fire(self, opts)
    end
  end

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
