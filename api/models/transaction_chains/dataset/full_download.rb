module TransactionChains
  class Dataset::FullDownload < Dataset::BaseDownload
    label 'Download'

    def download(dl)
      primary, backup = snap_in_pools(dl.snapshot)
      sip = backup || primary
      fail 'snapshot is nowhere to be found!' unless sip

      lock(sip)
      lock(sip.dataset_in_pool)

      dl.pool = sip.dataset_in_pool.pool
    end

    protected
    def snap_in_pools(snapshot)
      pr = bc = nil

      snapshot.snapshot_in_pools
          .includes(dataset_in_pool: [:pool])
          .joins(dataset_in_pool: [:pool])
          .all.group('pools.role').each do |sip|
        case sip.dataset_in_pool.pool.role.to_sym
          when :hypervisor, :primary
            pr = sip

          when :backup
            bc = sip
        end
      end

      [pr, bc]
    end
  end
end
