module VpsAdmin::API::Tasks
  class Snapshot < Base
    def purge_clones
      TransactionChains::SnapshotInPool::PurgeClones.fire
    end
  end
end
