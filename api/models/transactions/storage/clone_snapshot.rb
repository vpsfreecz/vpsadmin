require_relative '../utils/user_namespaces'

module Transactions::Storage
  class CloneSnapshot < ::Transaction
    t_name :storage_clone_snapshot
    t_type 5217
    queue :storage

    include Transactions::Utils::UserNamespaces

    def params(snapshot_in_pool, userns_map = nil)
      self.node_id = snapshot_in_pool.dataset_in_pool.pool.node_id

      ret = {
        pool_fs: snapshot_in_pool.dataset_in_pool.pool.filesystem,
        dataset_name: snapshot_in_pool.dataset_in_pool.dataset.full_name,
        snapshot_id: snapshot_in_pool.snapshot_id,
        snapshot: snapshot_in_pool.snapshot.name,
      }

      if snapshot_in_pool.dataset_in_pool.pool.role == 'backup'
        in_branch = ::SnapshotInPoolInBranch.joins(branch: [:dataset_tree]).find_by!(
          dataset_trees: {dataset_in_pool_id: snapshot_in_pool.dataset_in_pool_id},
          snapshot_in_pool_id: snapshot_in_pool.id
        )

        ret[:dataset_tree] = in_branch.branch.dataset_tree.full_name
        ret[:branch] = in_branch.branch.full_name
      end

      if userns_map
        ret.update(
          uidmap: build_map(userns_map, :uid),
          gidmap: build_map(userns_map, :gid),
        )
      end

      ret
    end
  end
end
