class SnapshotDownload < ActiveRecord::Base
  belongs_to :snapshot
  belongs_to :pool

  include Confirmable
  include Lockable

  def destroy
    TransactionChains::Dataset::RemoveDownload.fire(self)
  end
end
