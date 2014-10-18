module Transactions::Storage
  class BranchDataset < ::Transaction
    t_name :storage_create_branch_dataset
    t_type 5206

    def params(branch, src_snapshot_in_branch = nil)
      self.t_server = branch.dataset_in_pool.pool.node_id

      ret = {
          pool_fs: branch.dataset_in_pool.pool.filesystem,
          dataset_name: branch.dataset_in_pool.dataset.full_name,
          new_branch_name: branch.full_name,
      }

      if src_snapshot_in_branch
        ret[:from_branch_name] = src_snapshot_in_branch.branch.full_name,
        ret[:from_snapshot] = src_snapshot_in_branch.snapshot.name
      end

      ret
    end
  end
end
