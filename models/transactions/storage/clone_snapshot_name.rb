module Transactions::Storage
  class CloneSnapshotName < ::Transaction
    t_name :storage_clone_snapshot_name
    t_type 5224
    queue :storage

    def params(node, clones)
      self.t_server = node.id

      {
          snapshots: clones
      }
    end
  end
end
