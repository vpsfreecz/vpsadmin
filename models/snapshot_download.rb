class SnapshotDownload < ActiveRecord::Base
  belongs_to :user
  belongs_to :snapshot
  belongs_to :pool

  include Confirmable
  include Lockable

  include VpsAdmin::API::Lifetimes::Model
  set_object_states states: %i(active deleted),
                    deleted: {
                        enter: TransactionChains::Dataset::RemoveDownload
                    }

  enum format: %i(archive stream)

  def self.base_url
    return @base_url if @base_url
    @base_url = ::SysConfig.get('snapshot_download_base_url')
  end

  def destroy
    TransactionChains::Dataset::RemoveDownload.fire(self)
  end

  def url
    File.join(
        self.class.base_url,
        pool.node.fqdn,
        pool.filesystem.split('/').last,
        secret_key,
        file_name
    )
  end
end
