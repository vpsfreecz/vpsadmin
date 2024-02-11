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
        checksum: true
      }

      opts.on('-I', '--from-snapshot SNAPSHOT_ID', Integer, 'Download snapshot incrementally from SNAPSHOT_ID') do |s|
        @opts[:from_snapshot] = s
      end

      opts.on('-d', '--[no-]delete-after', 'Delete the file from the server after successful download') do |d|
        @opts[:delete_after] = d
      end

      opts.on('-q', '--quiet', 'Print only errors') do |q|
        @opts[:quiet] = q
      end

      opts.on('-s', '--[no-]send-mail', 'Send mail after the file for download is completed') do |s|
        @opts[:send_mail] = s
      end

      opts.on('-x', '--max-rate N', Integer, 'Maximum download speed in kB/s') do |r|
        exit_msg('--max-rate must be greater than zero') if r <= 0
        @opts[:max_rate] = r
      end

      opts.on('--[no-]checksum', 'Verify checksum of the downloaded data (enabled)') do |c|
        @opts[:checksum] = c
      end
    end

    def exec(args)
      if args.size != 1
        warn 'Provide exactly one SNAPSHOT_ID as an argument'
        exit(false)
      end

      opts = @opts.clone
      opts[:snapshot] = args.first.to_i

      do_exec(opts)
    end

    def do_exec(opts)
      @opts = opts
      opts[:format] = opts[:from_snapshot] ? :incremental_stream : :stream

      dl, created = find_or_create_dl(opts)

      if created
        warn_msg 'The download is being prepared...'
        sleep(5)

      else
        warn_msg "Reusing existing SnapshotDownload (id=#{dl.id})"
      end

      r, w = IO.pipe

      pid = Process.fork do
        r.close

        begin
          VpsAdmin::CLI::StreamDownloader.download(
            @api,
            dl,
            w,
            progress: !opts[:quiet] && $stderr,
            max_rate: opts[:max_rate],
            checksum: opts[:checksum]
          )
        rescue VpsAdmin::CLI::DownloadError => e
          warn e.message
          exit(false)
        end
      end

      w.close

      gz = Zlib::GzipReader.new(r)
      $stdout.write(gz.readpartial(16 * 1024)) until gz.eof?
      gz.close

      Process.wait(pid)
      exit($?.exitstatus) if $?.exitstatus != 0

      @api.snapshot_download.delete(dl.id) if opts[:delete_after]
    end
  end
end
