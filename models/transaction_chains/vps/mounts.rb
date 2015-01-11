module TransactionChains
  # Create /etc/vz/conf/$veid.(u)mount scripts.
  # Contains mounts of storage datasets (NAS) and VPS subdatasets.
  class Vps::Mounts < ::TransactionChain
    label 'Mounts'

    def link_chain(vps)
      lock(vps)

      @vps = vps
      mounts = []

      # Subdatasets
      vps.dataset_in_pool.dataset.subtree.arrange.each do |k, v|
        mounts.concat(recursive_subdataset(k, v))
      end

      # Remove the first dataset, it is the top-level dataset with VPS private area
      mounts.shift

      # Remote mounts
      vps.mounts.all.each do |m|
        mounts << m
      end

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
      unless ds.dataset_in_pools
                .where(pool_id: @vps.dataset_in_pool.pool_id)
                .where.not(confirmed: ::DatasetInPool.confirmed(:confirm_destroy)).any?

        return false
      end

      {
          type: :zfs,
          pool_fs: @vps.dataset_in_pool.pool.filesystem,
          dataset: ds.full_name
      }
    end
  end
end
