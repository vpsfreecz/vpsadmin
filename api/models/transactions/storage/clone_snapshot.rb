require_relative '../utils/user_namespaces'

module Transactions::Storage
  class CloneSnapshot < ::Transaction
    t_name :storage_clone_snapshot
    t_type 5217
    queue :storage

    include Transactions::Utils::UserNamespaces

    # @param [::SnapshotInPoolClone]
    def params(cl)
      self.node_id = cl.snapshot_in_pool.dataset_in_pool.pool.node_id

      ret = {
        clone_name: cl.name,
        pool_fs: cl.snapshot_in_pool.dataset_in_pool.pool.filesystem,
        dataset_name: cl.snapshot_in_pool.dataset_in_pool.dataset.full_name,
        snapshot_id: cl.snapshot_in_pool.snapshot_id,
        snapshot: cl.snapshot_in_pool.snapshot.name,
      }

      if cl.snapshot_in_pool.dataset_in_pool.pool.role == 'backup'
        in_branch = ::SnapshotInPoolInBranch.joins(branch: [:dataset_tree]).find_by!(
          dataset_trees: {dataset_in_pool_id: cl.snapshot_in_pool.dataset_in_pool_id},
          snapshot_in_pool_id: cl.snapshot_in_pool_id
        )

        ret[:dataset_tree] = in_branch.branch.dataset_tree.full_name
        ret[:branch] = in_branch.branch.full_name
      end

      if cl.user_namespace_map_id
        ret.update(
          uidmap: build_map(cl.user_namespace_map, :uid),
          gidmap: build_map(cl.user_namespace_map, :gid),
        )
      end

      ret
    end
  end
end
