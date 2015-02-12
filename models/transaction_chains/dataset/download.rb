module TransactionChains
  class Dataset::Download < ::TransactionChain
    label 'Download snapshot'

    def link_chain(snapshot)
      primary, backup = snap_in_pools(snapshot)
      sip = backup || primary
      fail 'snapshot is nowhere to be found!' unless sip

      lock(sip)
      lock(sip.dataset_in_pool)

      dl = ::SnapshotDownload.new(
          user: ::User.current,
          snapshot: snapshot,
          pool: sip.dataset_in_pool.pool,
          secret_key: generate_key,
          file_name: "#{sip.dataset_in_pool.dataset.full_name.gsub(/\//, '_')}__#{snapshot.name.gsub(/:/, '-')}.tar.gz",
          confirmed: ::SnapshotDownload.confirmed(:confirm_create)
      )

      tries = 0

      begin
        dl.save!

      rescue ActiveRecord::RecordNotUnique
        fail 'run out of tries' if tries == 10

        dl.secret_key = generate_key
        tries += 1
        retry
      end

      append(Transactions::Storage::DownloadSnapshot, args: [dl, sip]) do
        create(dl)
        edit(snapshot, snapshot_download_id: dl.id)
      end

      dl
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

    def generate_key
      SecureRandom.hex(50)
    end
  end
end
