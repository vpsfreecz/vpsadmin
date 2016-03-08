module VpsAdmin::CLI::Commands
  class SnapshotDownload < BaseDownload
    cmd :snapshot, :download
    args 'SNAPSHOT_ID'
    desc 'Download a snapshot as an archive or a stream'

    def options(opts)
      @opts = {
          delete_after: true,
          send_mail: false,
      }

      opts.on('-f', '--format FORMAT', 'archive, stream or incremental_stream') do |f|
        @opts[:format] = f
      end
      
      opts.on('-I', '--from-snapshot SNAPSHOT_ID', 'Download snapshot incrementally from SNAPSHOT_ID') do |s|
        @opts[:from_snapshot] = s.to_i
      end

      opts.on('-d', '--[no-]delete-after', 'Delete the file from the server after successful download') do |d|
        @opts[:delete_after] = d
      end

      opts.on('-s', '--[no-]send-mail', 'Send mail after the file for download is completed') do |s|
        @opts[:send_mail] = s
      end
    end

    def exec(args)
      if args.size != 1
        warn "Provide exactly one SNAPSHOT_ID as an argument"
        exit(false)
      end

      opts = @opts.clone
      opts[:snapshot] = args.first.to_i

      dl, created = find_or_create_dl(opts)

      if created
        warn "The download is being prepared..."
        sleep(5)

      else
        warn "Reusing existing SnapshotDownload (id=#{dl.id})"
      end
      
      f = File.open(dl.file_name, 'w')

      begin
        VpsAdmin::CLI::StreamDownloader.download(@api, dl, f)

      rescue VpsAdmin::CLI::DownloadError => e
        warn e.message
        exit(false)
        
      ensure
        f.close
      end

      @api.snapshot_download.delete(dl.id) if @opts[:delete_after]
    end
  end
end 
