module TransactionChains
  class Vps::Restore < Dataset::Rollback
    label 'Restore VPS'

    def link_chain(vps, snapshot)
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
