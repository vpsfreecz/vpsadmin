module Transactions::Utils
  module Mounts
    def mount_params(mnt)
      if mnt.is_a?(::Mount)
        m = {}

        # Mount of dataset in pool
        if mnt.dataset_in_pool_id
          fail 'not implemented'

          # Mount of snapshot in pool
        elsif mnt.snapshot_in_pool_id
          # Mount it locally
          if mnt.snapshot_in_pool.dataset_in_pool.pool.node_id == mnt.vps.vps_server
            m[:type] = :snapshot_local

            # Mount via NFS
          else
            m[:type] = :snapshot_remote
            m[:src_node_addr] = mnt.snapshot_in_pool.dataset_in_pool.pool.node.addr
          end

          m.update({
              pool_fs: mnt.snapshot_in_pool.dataset_in_pool.pool.filesystem,
              snapshot_id: mnt.snapshot_in_pool_id,
              snapshot: mnt.snapshot_in_pool.snapshot.name,
              dst: mnt.dst,
              mount_opts: mnt.mount_opts,
              umount_opts: mnt.umount_opts,
              mode: mnt.mode,
              runscripts: false
          })
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
