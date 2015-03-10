module TransactionChains
  class Vps::Restore < Dataset::Rollback
    label 'Restore VPS'

    def link_chain(vps, snapshot)
      lock(vps)
      set_concerns(:affect, [vps.class.name, vps.id])

      @vps = vps

      dip = snapshot.dataset.dataset_in_pools.where(pool_id: vps.dataset_in_pool.pool_id).take!

      super(dip, snapshot)
    end

    def pre_local_rollback
      use_chain(Vps::Stop, args: @vps)
    end

    def post_local_rollback
      use_chain(Vps::Start, args: @vps)
    end
  end
end
