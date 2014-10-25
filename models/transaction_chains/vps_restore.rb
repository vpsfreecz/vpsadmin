module TransactionChains
  class VpsRestore < DatasetRollback
    label 'Restore VPS'

    def link_chain(vps, snapshot)
      @vps = vps
      super(vps.dataset_in_pool, snapshot)
    end

    def pre_local_rollback
      use_chain(VpsStop, @vps)
    end

    def post_local_rollback
      use_chain(VpsStart, @vps)
    end
  end
end
