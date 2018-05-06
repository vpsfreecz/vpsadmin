module Transactions::Utils
  module Mounts
    def mount_params(mnt)
      if mnt.is_a?(::Mount)
        m = {
          id: mnt.id,
          on_start_fail: mnt.on_start_fail,
        }

        # Mount of dataset in pool
        if mnt.dataset_in_pool_id && !mnt.snapshot_in_pool_id

          # Mount it locally
          if mnt.dataset_in_pool.pool.node_id == mnt.vps.node_id
            m[:type] = :dataset_local

          # Mount via NFS
          else
            m[:type] = :dataset_remote
            m[:src_node_addr] = mnt.dataset_in_pool.pool.node.addr
          end

          m.update({
            pool_fs: mnt.dataset_in_pool.pool.filesystem,
            dataset_name: mnt.dataset_in_pool.dataset.full_name,
            dst: mnt.dst,
            mount_opts: mnt.mount_opts,
            umount_opts: mnt.umount_opts,
            mode: mnt.mode,
          })

        # Mount of snapshot in pool
        elsif mnt.snapshot_in_pool_id

          # Mount it locally
          if mnt.snapshot_in_pool.dataset_in_pool.pool.node_id == mnt.vps.node_id
            m[:type] = :snapshot_local

            # Mount via NFS
          else
            m[:type] = :snapshot_remote
            m[:src_node_addr] = mnt.snapshot_in_pool.dataset_in_pool.pool.node.addr
          end

          m.update({
            pool_fs: mnt.snapshot_in_pool.dataset_in_pool.pool.filesystem,
            dataset_name: mnt.snapshot_in_pool.dataset_in_pool.dataset.full_name,
            snapshot_id: mnt.snapshot_in_pool.snapshot_id,
            snapshot: mnt.snapshot_in_pool.snapshot.name,
            dst: mnt.dst,
            mount_opts: mnt.mount_opts,
            umount_opts: mnt.umount_opts,
            mode: mnt.mode,
          })

          if mnt.snapshot_in_pool.dataset_in_pool.pool.role == 'backup'
            sipib = mnt.snapshot_in_pool.snapshot_in_pool_in_branches.includes(
              branch: [:dataset_tree]
            ).joins(
              branch: [:dataset_tree]
            ).where(
              dataset_trees: {dataset_in_pool_id: mnt.snapshot_in_pool.dataset_in_pool.id},
            ).take!

            m.update({
              dataset_tree: sipib.branch.dataset_tree.full_name,
              branch: sipib.branch.full_name,
            })
          end
        end

        m

      elsif mnt.is_a?(::Hash)
        mnt

      else
        fail 'invalid mount type'
      end
    end
  end
end
