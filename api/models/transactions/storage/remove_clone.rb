module Transactions::Storage
  class RemoveClone < ::Transaction
    t_name :storage_remove_clone
    t_type 5218
    queue :storage
    irreversible

    include Transactions::Utils::UserNamespaces

    # @param cl [::SnapshotInPoolClone]
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
