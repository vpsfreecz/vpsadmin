module TransactionChains
  class Dataset::BaseDownload < ::TransactionChain
    label 'Download'

    def link_chain(snapshot, format, from_snapshot = nil)
      concerns(:affect, [snapshot.class.name, snapshot.id])

      dl = ::SnapshotDownload.new(
          user: ::User.current,
          snapshot: snapshot,
          from_snapshot: from_snapshot,
          secret_key: generate_key,
          format: format,
          file_name: filename(snapshot, format, from_snapshot),
          expiration_date: Time.now + 7 * 24 * 60 * 60,
          confirmed: ::SnapshotDownload.confirmed(:confirm_create)
      )

      download(dl)

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
          queue: format == :stream ? :zfs_send : nil,
      ) do
        create(dl)
        edit(snapshot, snapshot_download_id: dl.id)
      end

      mail(:snapshot_download_ready, {
          user: ::User.current,
          vars: {
              dl: dl
          }
      })

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
