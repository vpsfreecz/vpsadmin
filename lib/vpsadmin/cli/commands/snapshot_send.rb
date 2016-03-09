require 'zlib'

module VpsAdmin::CLI::Commands
  class SnapshotSend < BaseDownload
    cmd :snapshot, :send
    args 'SNAPSHOT_ID'
    desc 'Download a snapshot stream and write it on stdout'

    def options(opts)
      @opts = {
          delete_after: true,
          send_mail: false,
      }
      
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

      do_exec(opts)
    end

    def do_exec(opts)
      opts[:format] = opts[:from_snapshot] ? :incremental_stream : :stream

      dl, created = find_or_create_dl(opts)

      if created
        warn "The download is being prepared..."
        sleep(5)

      else
        warn "Reusing existing SnapshotDownload (id=#{dl.id})"
      end

      r, w = IO.pipe

      pid = Process.fork do
        r.close

        begin
          VpsAdmin::CLI::StreamDownloader.download(@api, dl, w, progress: STDERR)

        rescue VpsAdmin::CLI::DownloadError => e
          warn e.message
          exit(false)
        end
      end

      w.close

      gz = Zlib::GzipReader.new(r)
      STDOUT.write(gz.readpartial(16*1024)) while !gz.eof?
      gz.close

      Process.wait(pid)
      exit($?.exitstatus) if $?.exitstatus != 0

      @api.snapshot_download.delete(dl.id) if opts[:delete_after]
    end
  end
end
