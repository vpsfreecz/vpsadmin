module TransactionChains
  class Vps::Restore < Dataset::Rollback
    label 'Restore VPS'

    def link_chain(vps, snapshot)
      @vps = vps
      super(vps.dataset_in_pool, snapshot)
    end

    def pre_local_rollback
      use_chain(Vps::Stop, @vps)
    end

    def post_local_rollback
      use_chain(Vps::Start, @vps)
    end
  end
end
