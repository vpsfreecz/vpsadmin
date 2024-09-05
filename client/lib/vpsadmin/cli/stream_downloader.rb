require 'uri'
require 'net/http'
require 'ruby-progressbar'
require 'digest'

module VpsAdmin::CLI
  class DownloadError < StandardError; end

  class StreamDownloader
    def self.download(*args, **kwargs)
      new(*args, **kwargs)
    end

    def initialize(api, dl, io, progress: $stdout, position: 0, max_rate: nil,
                   checksum: true)
      downloaded = position
      uri = URI(dl.url)
      digest = Digest::SHA256.new
      dl_check = nil

      if position > 0 && checksum
        if progress
          pb = ProgressBar.create(
            title: 'Calculating checksum',
            total: position,
            format: '%E %t: [%B] %p%% %r MB/s',
            rate_scale: ->(rate) { (rate / 1024.0 / 1024.0).round(2) },
            throttle_rate: 0.2,
            output: progress
          )
        end

        read = 0
        step = 1 * 1024 * 1024
        io.seek(0)

        while read < position
          data = io.read((read + step) > position ? position - read : step)
          read += data.size

          digest << data
          pb.progress = read if pb
        end

        pb.finish if pb
      end

      if progress
        self.format = '%t: [%B] %r kB/s'

        @pb = ProgressBar.create(
          title: 'Downloading',
          total: nil,
          format: @format,
          rate_scale: ->(rate) { (rate / 1024.0).round(2) },
          throttle_rate: 0.2,
          starting_at: downloaded,
          autofinish: false,
          output: progress
        )
      end

      args = [uri.host] + Array.new(5, nil) + [{ use_ssl: uri.scheme == 'https' }]

      Net::HTTP.start(*args) do |http|
        loop do
          begin
            dl_check = api.snapshot_download.show(dl.id)

            if @pb && (dl_check.ready || (dl_check.size && dl_check.size > 0)) # rubocop:disable all
              total = dl_check.size * 1024 * 1024
              @pb.total = [@pb.progress, total].max

              @download_size = (dl_check.size / 1024.0).round(2)

              if dl_check.ready
                @download_ready = true
                self.format = "%E %t #{@download_size} GB: [%B] %p%% %r kB/s"

              else
                self.format = "%E %t ~#{@download_size} GB: [%B] %p%% %r kB/s"
              end
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
            case res.code
            when '404' # Not Found
              raise DownloadError, 'The download has failed, most likely transaction failure' if downloaded > 0

              # This means that the transaction used for preparing the download
              # has failed, the file to download does not exist anymore, so fail.

              # The file is not available yet, this is normal, the transaction
              # may be queued and it can take some time before it is processed.
              pause(10)
              next

            when '416' # Range Not Satisfiable
              raise DownloadError, 'Range not satisfiable' unless downloaded > position

              # We have already managed to download something (at this run, if the trasfer
              # was resumed) and the server cannot provide more data yet. This can be
              # because the server is busy. Wait and retry.
              pause(20)
              next

            # The file is not ready yet - we ask for range that cannot be provided
            # This happens when we're resuming a download and the file on the
            # server was deleted meanwhile. The file might not be exactly the same
            # as the one before, sha256sum would most likely fail.

            when '200', '206' # OK and Partial Content
              resume

            else
              raise DownloadError, "Unexpected HTTP status code '#{res.code}'"
            end

            t1 = Time.now
            data_counter = 0

            res.read_body do |fragment|
              size = fragment.size

              data_counter += size
              downloaded += size

              begin
                @pb.progress += size if @pb && (@pb.total.nil? || @pb.progress < @pb.total)
              rescue ProgressBar::InvalidProgressError
                # The total value is in MB, it is not precise, so the actual
                # size may be a little bit bigger.
                @pb.progress = @pb.total
              end

              digest.update(fragment) if checksum

              if max_rate && max_rate > 0
                t2 = Time.now
                diff = t2 - t1

                if diff > 0.005
                  # Current and expected rates in kB per interval +diff+
                  current_rate = data_counter / 1024
                  expected_rate = max_rate * diff

                  if current_rate > expected_rate
                    delay = diff / (expected_rate / (current_rate - expected_rate))
                    sleep(delay)
                  end

                  data_counter = 0
                  t1 = Time.now
                end
              end

              io.write(fragment)
            end
          end

          # This was the last download, the transfer is complete.
          break if dl_check.ready

          # Give the server time to prepare additional data
          pause(15)
        end
      end

      @pb.finish if @pb

      # Verify the checksum
      return unless checksum && digest.hexdigest != dl_check.sha256sum

      raise DownloadError, 'The sha256sum does not match, retry the download'
    end

    protected

    def pause(secs)
      @paused = true

      if @pb
        secs.times do |i|
          if @download_size
            if @download_ready
              @pb.format("%t #{@download_size} GB: [%B] waiting #{secs - i}")

            else
              @pb.format("%t ~#{@download_size} GB: [%B] waiting #{secs - i}")
            end

          else
            @pb.format("%t: [%B] waiting #{secs - i}")
          end

          @pb.refresh(force: true)
          sleep(1)
        end

      else
        sleep(secs)
      end
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
