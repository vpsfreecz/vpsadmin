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

      opts.on('-f', '--force', 'Overwrite existing files if necessary') do |f|
        @opts[:force] = f
      end

      opts.on('-o', '--output FILE', 'Save the download to FILE') do |f|
        @opts[:file] = f
      end

      opts.on('-r', '--resume', 'Resume cancelled download') do |r|
        @opts[:resume] = r
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
     
      f = nil
      pos = 0

      if @opts[:file] == '-'
        f = STDOUT

      else
        path = @opts[:file] || dl.file_name

        if File.exists?(path)
          action = nil

          if @opts[:resume]
            action = :resume

          elsif @opts[:force]
            action = :overwrite

          elsif STDIN.tty?
            while action.nil?
              STDERR.write("'#{path}' already exists. [A]bort, [r]esume or [o]verwrite? [a]: ")
              STDERR.flush

              action = {
                  'r' => :resume,
                  'o' => :overwrite,
                  '' => false,
              }[STDIN.readline.strip.downcase]
            end

          else
            warn "File '#{path}' already exists"
            exit(false)
          end
          
          case action
          when :resume
            mode = 'a+'
            pos = File.size(path)

          when :overwrite
            mode = 'w'

          else
            exit
          end

          f = File.open(path, mode)

        else
          f = File.open(path, 'w')
        end
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

      begin
        VpsAdmin::CLI::StreamDownloader.download(
            @api,
            dl,
            f,
            progress: f == STDOUT ? STDERR : STDOUT,
            position: pos,
        )

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
