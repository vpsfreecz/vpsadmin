module TransactionChains
  # Umount local or remote datasets without VPS restart.
  # All descendant datasets are umounted as well.
  class Vps::Umount < ::TransactionChain
    label 'Umount'

    def link_chain(vps, mounts)
      lock(vps)

      @vps = vps

      mounts = [mounts] unless mounts.is_a?(Array)
      res = []

      mounts.each do |mnt|
        if mnt.is_a?(::DatasetInPool)
          mnt.dataset.subtree.arrange.each do |k, v|
            res.concat(recursive_umount(k, v))
          end

        else
          res << mnt
        end
      end

      append(Transactions::Vps::Umount, args: [vps, res])
    end

    def recursive_umount(dataset, children)
      ret = []

      top_dip = find_in_pool(dataset)
      return ret unless top_dip

      children.each do |k, v|
        if v.is_a?(::Dataset)
          dip = find_in_pool(v)
          ret << dip if dip

        else
          ret.concat(recursive_umount(k, v))
        end
      end

      ret << top_dip
      ret
    end

    def find_in_pool(ds)
      ds.dataset_in_pools.where(pool_id: @vps.dataset_in_pool.pool_id).take
    end
  end
end
