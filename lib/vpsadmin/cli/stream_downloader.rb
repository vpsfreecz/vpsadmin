require 'uri'
require 'net/http'
require 'ruby-progressbar'
require 'digest'

module VpsAdmin::CLI
  class DownloadError < StandardError ; end

  class StreamDownloader
    def self.download(*args)
      new(*args)
    end

    def initialize(api, dl, io, progress: STDOUT, position: 0)
      downloaded = position
      uri = URI(dl.url)
      digest = Digest::SHA256.new
      dl_check = nil

      if position > 0
        io.seek(0)
        digest << io.read(position)
      end

      if progress
        self.format = '%t: [%B] %r kB/s'

        @pb = ProgressBar.create(
            total: nil,
            format: @format,
            rate_scale: ->(rate) { (rate / 1024.0).round(2) },
            throttle_rate: 0.05,
            output: progress,
        )
      end

      Net::HTTP.start(uri.host) do |http|
        loop do
          begin
            dl_check = api.snapshot_download.show(dl.id)

            if @pb && dl_check.ready
              @pb.progress = downloaded

              total = dl_check.size * 1024 * 1024
              @pb.total = @pb.progress > total ? @pb.progress : total

              self.format = '%E: [%B] %p%% %r kB/s'
            end

          rescue HaveAPI::Client::ActionFailed => e
            # The SnapshotDownload object no longer exists, the transaction
            # responsible for its creation must have failed.
            stop
            raise DownloadError, 'The download has failed due to transaction failure'
          end

          headers = {}
          headers['Range'] = "bytes=#{downloaded}-" if downloaded > 0

          http.request_get(uri.path, headers) do |res|
            case res.code.to_i
            when 404  # Not Found
              if downloaded > 0
                # This means that the transaction used for preparing the download
                # has failed, the file to download does not exist anymore, so fail.
                raise DownloadError, 'The download has failed, most likely transaction failure'

              else
                # The file is not available yet, this is normal, the transaction
                # may be queued and it can take some time before it is processed.
                pause(10)
                next
              end

            when 416  # Range Not Satisfiable
              # The file is not ready yet - we ask for range that cannot be provided
              # yet. This happens when we're resuming a download and the file on the
              # server was deleted meanwhile. The file might not be exactly the same
              # as the one before, sha256sum would most likely fail.
              raise DownloadError, 'Range not satisfiable'

            else
              resume
            end
            
            res.read_body do |fragment|
              size = fragment.size
              downloaded += size

              begin
                if @pb && (@pb.total.nil? || @pb.progress < @pb.total)
                  @pb.progress += size
                end

              rescue ProgressBar::InvalidProgressError
                # The total value is in MB, it is not precise, so the actual
                # size may be a little bit bigger.
                @pb.progress = @pb.total
              end

              digest.update(fragment)
              io.write(fragment)
            end
          end

          # This was the last download, the transfer is complete.
          break if dl_check.ready

          # Give the server time to prepare additional data
          pause(15)
        end
      end

      # Verify the checksum
      if digest.hexdigest != dl_check.sha256sum
        raise DownloadError, 'The sha256sum does not match, retry the download'
      end
    end

    protected
    def pause(secs)
      @pb.format('%t: [%B] waiting') if @pb && !@paused
      @paused = true

      sleep(secs)
    end

    def resume
      @pb.format(@format) if @pb && @paused
      @paused = false
    end

    def stop
      @pb.stop if @pb
    end

    def format=(fmt)
      @format = fmt
      @pb.format(@format) if @pb
    end
  end
end
