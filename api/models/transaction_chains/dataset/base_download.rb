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
        snapshot: snapshot,
        from_snapshot: opts[:from_snapshot],
        secret_key: generate_key,
        format: opts[:format],
        file_name: filename(snapshot, opts[:format], opts[:from_snapshot]),
        expiration_date: Time.now + 7 * 24 * 60 * 60,
        confirmed: ::SnapshotDownload.confirmed(:confirm_create)
      )

      download(dl)

      dl.pool.node.maintenance_check!(dl.pool)

      tries = 0

      begin
        dl.save!

      rescue ActiveRecord::RecordNotUnique
        fail 'run out of tries' if tries == 10

        dl.secret_key = generate_key
        tries += 1
        retry
      end

      append(
        Transactions::Storage::DownloadSnapshot,
        args: dl,
        queue: opts[:format] == :archive ? nil : :zfs_send,
      ) do
        create(dl)
        edit(snapshot, snapshot_download_id: dl.id)
      end

      mail(:snapshot_download_ready, {
        user: ::User.current,
        vars: {
          base_url: ::SysConfig.get(:webui, :base_url),
          dl: dl,
        }
      }) if opts[:send_mail]

      dl
    end

    protected
    def download(dl)
      raise NotImplementedError
    end

    def filename(snapshot, format, from_snapshot)
      ds = snapshot.dataset.full_name.gsub(/\//, '_')
      base = "#{ds}__#{snapshot.name.gsub(/:/, '-')}"

      case format
      when :archive
        "#{base}.tar.gz"

      when :stream
        "#{base}.dat.gz"

      when :incremental_stream
        "#{ds}__#{from_snapshot.name.gsub(/:/, '-')}__#{snapshot.name.gsub(/:/, '-')}.inc.dat.gz"

      else
        fail "unsupported format '#{format}'"
      end
    end

    def generate_key
      SecureRandom.hex(50)
    end
  end
end
