module TransactionChains
  class Dataset::BaseDownload < ::TransactionChain
    label 'Download'

    # @param opts [Hash]
    # @option opts [Symbol] format
    # @option opts [Snapshot] from_snapshot
    # @option opts [Boolean] send_mail
    def link_chain(snapshot, opts)
      concerns(:affect, [snapshot.class.name, snapshot.id])

      dl = ::SnapshotDownload.new(
        user: ::User.current,
        snapshot:,
        from_snapshot: opts[:from_snapshot],
        secret_key: generate_key,
        format: opts[:format],
        file_name: filename(snapshot, opts[:format], opts[:from_snapshot]),
        expiration_date: Time.now + (7 * 24 * 60 * 60),
        confirmed: ::SnapshotDownload.confirmed(:confirm_create)
      )

      download(dl)

      dl.pool.node.maintenance_check!(dl.pool)

      tries = 0

      begin
        dl.save!
      rescue ActiveRecord::RecordNotUnique
        raise 'run out of tries' if tries == 10

        dl.secret_key = generate_key
        tries += 1
        retry
      end

      append(
        Transactions::Storage::DownloadSnapshot,
        args: dl,
        queue: opts[:format] == :archive ? nil : :zfs_send
      ) do
        create(dl)
        edit(snapshot, snapshot_download_id: dl.id)
      end

      if opts[:send_mail]
        dataset = snapshot.dataset
        route_event!(
          'snapshot.download_ready',
          user: ::User.current,
          source: dl,
          subject: 'Snapshot download is ready',
          summary: "#{dataset.full_name}@#{snapshot.name}",
          parameters: {
            download_id: dl.id,
            snapshot_id: snapshot.id,
            snapshot_name: snapshot.name,
            dataset_id: dataset.id,
            dataset_full_name: dataset.full_name,
            file_name: dl.file_name,
            format: dl.format,
            expiration_date: dl.expiration_date&.iso8601
          }
        )
      end

      dl
    end

    protected

    def download(dl)
      raise NotImplementedError
    end

    def snapshot_download_unavailable!(*snapshots, reason:)
      snapshots = snapshots.compact.uniq
      snapshot_in_pools = ::SnapshotInPool.includes(dataset_in_pool: [:pool])
                                          .where(snapshot: snapshots)
                                          .order(:id)
                                          .to_a
      dataset_in_pools = snapshot_in_pools.filter_map(&:dataset_in_pool).uniq

      resource_lock = external_resource_lock(
        'SnapshotInPool',
        snapshot_in_pools.map(&:id)
      )
      locked_resource = snapshot_in_pools.find { |sip| sip.id == resource_lock&.row_id }

      unless resource_lock
        resource_lock = external_resource_lock(
          'DatasetInPool',
          dataset_in_pools.map(&:id)
        )
        locked_resource = dataset_in_pools.find { |dip| dip.id == resource_lock&.row_id }
      end

      if resource_lock
        raise ::ResourceLocked.new(locked_resource, 'snapshot download source is locked')
      end

      raise VpsAdmin::API::Exceptions::SnapshotDownloadUnavailable.new(
        snapshots,
        snapshot_in_pools,
        reason:
      )
    end

    def external_resource_lock(resource, row_ids)
      return if row_ids.empty?

      ::ResourceLock.where(resource:, row_id: row_ids).order(:row_id).detect do |lock|
        lock.locked_by_id != dst_chain.id ||
          lock.locked_by_type != dst_chain.class.polymorphic_name
      end
    end

    def filename(snapshot, format, from_snapshot)
      ds = snapshot.dataset.full_name.gsub(%r{/}, '_')
      base = "#{ds}__#{snapshot.name.gsub(':', '-')}"

      case format
      when :archive
        "#{base}.tar.gz"

      when :stream
        "#{base}.dat.gz"

      when :incremental_stream
        "#{ds}__#{from_snapshot.name.gsub(':', '-')}__#{snapshot.name.gsub(':', '-')}.inc.dat.gz"

      else
        raise "unsupported format '#{format}'"
      end
    end

    def generate_key
      SecureRandom.hex(50)
    end
  end
end
