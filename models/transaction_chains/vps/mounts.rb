module TransactionChains
  # Create /etc/vz/conf/$veid.(u)mount scripts.
  # Contains mounts of storage datasets (NAS) and VPS subdatasets.
  class Vps::Mounts < ::TransactionChain
    label 'Mounts'

    def link_chain(vps)
      lock(vps)

      @vps = vps

      mounts = []

      # FIXME: storage mounts
      # vps.vps_mounts.all.each do |m|
      #   if m.storage_export_id
      #     src = "#{m.storage_export.storage_root.node.addr}:#{m.storage_export.storage_root.root_path}/#{m.storage_export.path}"
      #
      #   elsif !m.server_id.nil? && m.server_id != 0
      #     src = "#{m.node.addr}:#{m.src}"
      #
      #   else
      #     src = m.src
      #   end
      #
      #   mounts << {
      #       src: src,
      #       dst: m.dst,
      #       mount_opts: m.mount_opts,
      #       umount_opts: m.umount_opts,
      #       mode: m.mode
      #   }
      #
      #   if cmds
      #     mounts.last.update({
      #                            premount: m.cmd_premount,
      #                            postmount: m.cmd_postmount,
      #                            preumount: m.cmd_preumount,
      #                            postumount: m.cmd_postumount
      #                        })
      #   end
      # end

      vps.dataset_in_pool.dataset.subtree.arrange.each do |k, v|
        mounts.concat(recursive_subdataset(k, v))
      end

      # Remove the first dataset, it is the top-level dataset with VPS private area
      mounts.shift

      append(Transactions::Vps::Mounts, args: [vps, mounts])
    end

    def recursive_subdataset(dataset, children)
      ret = []

      # Top level dataset first
      m = mountpoint_of(dataset)
      return ret unless m
      ret << m

      children.each do |k, v|
        if v.is_a?(::Dataset)
          m = mountpoint_of(v)
          ret << m if m

        else
          ret.concat(recursive_subdataset(k, v))
        end
      end

      ret
    end

    def mountpoint_of(ds)
      return false unless ds.dataset_in_pools.where(pool_id: @vps.dataset_in_pool.pool_id).any?

      {
          type: :zfs,
          pool_fs: @vps.dataset_in_pool.pool.filesystem,
          dataset: ds.full_name
      }
    end
  end
end
