module VpsAdmin::CLI
  class DownloadError < StandardError ; end

  class StreamDownloader
    def self.download(api, dl, io, progress: STDOUT)
      downloaded = 0
      uri = URI(dl.url)

      if progress
        pb = ProgressBar.create(
            total: nil,
            format: '%t: |%B| %r kB/s',
            rate_scale: ->(rate) { (rate / 1024.0).round(2) },
            output: progress,
        )

      else
        pb = nil
      end

      Net::HTTP.start(uri.host) do |http|
        loop do
          if pb
            pb.format = '%t: |%B| %r kB/s'
            pb.resume
          end

          begin
            dl_check = api.snapshot_download.show(dl.id)

            if pb && dl_check.ready
              pb.progress = downloaded
              pb.total = dl_check.size * 1024 * 1024
              pb.format = '%E: |%B| %p%% %r kB/s'
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
                sleep 5
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

              io.write(fragment)
            end
          end

          # This was the last download, the transfer is complete.
          break if dl_check.ready

          # Give the server time to prepare additional data
          if pb
            pb.format('%t: |%B| waiting')
            pb.pause
          end

          sleep(15)
        end
      end
    end
  end
end
