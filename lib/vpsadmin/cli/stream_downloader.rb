require 'uri'
require 'net/http'
require 'ruby-progressbar'
require 'digest'

module VpsAdmin::CLI
  class DownloadError < StandardError ; end

  class StreamDownloader
    def self.download(api, dl, io, progress: STDOUT, position: 0)
      downloaded = position
      uri = URI(dl.url)
      digest = Digest::SHA256.new
      dl_check = nil

      if position > 0
        io.seek(0)
        digest << io.read(position)
      end

      if progress
        pb = ProgressBar.create(
            total: nil,
            format: '%t: |%B| %r kB/s',
            rate_scale: ->(rate) { (rate / 1024.0).round(2) },
            throttle_rate: 0.05,
            output: progress,
        )

      else
        pb = nil
      end

      Net::HTTP.start(uri.host) do |http|
        loop do
          if pb
            pb.format = '%t: [%B] %r kB/s'
            pb.resume
          end

          begin
            dl_check = api.snapshot_download.show(dl.id)

            if pb && dl_check.ready
              pb.progress = downloaded

              total = dl_check.size * 1024 * 1024
              pb.total = pb.progress > total ? pb.progress : total

              pb.format = '%E: [%B] %p%% %r kB/s'
            end

          rescue HaveAPI::Client::ActionFailed => e
            # The SnapshotDownload object no longer exists, the transaction
            # responsible for its creation must have failed.
            pb.stop if pb
            raise DownloadError, 'The download has failed due to transaction failure'
          end

          headers = {}
          headers['Range'] = "bytes=#{downloaded}-" if downloaded > 0

          http.request_get(uri.path, headers) do |res|
            if res.code == 404
              if downloaded > 0
                # This means that the transaction used for preparing the download
                # has failed, the file to download does not exist anymore, so fail.
                raise DownloadError, 'The download has failed, most likely transaction failure'

              else
                # The file is not available yet, this is normal, the transaction
                # may be queued and it can take some time before it is processed.
                pb.pause
                sleep(10)
                next
              end
            end
            
            res.read_body do |fragment|
              size = fragment.size
              downloaded += size

              begin
                if pb && (pb.total.nil? || pb.progress < pb.total)
                  pb.progress += size
                end

              rescue ProgressBar::InvalidProgressError
                # The total value is in MB, it is not precise, so the actual
                # size may be a little bit bigger.
                pb.progress = pb.total
              end

              digest.update(fragment)
              io.write(fragment)
            end
          end

          # This was the last download, the transfer is complete.
          break if dl_check.ready

          # Give the server time to prepare additional data
          if pb
            pb.format('%t: [%B] waiting')
            pb.pause
          end

          sleep(15)
        end
      end

      # Verify the checksum
      if digest.hexdigest != dl_check.sha256sum
        raise DownloadError, 'The sha256sum does not match, retry the download'
      end
    end
  end
end
