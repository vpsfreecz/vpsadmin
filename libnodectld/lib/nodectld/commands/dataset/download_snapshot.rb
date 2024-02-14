require 'digest'
require 'fileutils'
require 'pathname'

module NodeCtld
  class Commands::Dataset::DownloadSnapshot < Commands::Base
    handle 5004
    needs :system, :zfs, :pool

    def exec
      ds = "#{@pool_fs}/#{@dataset_name}"
      ds += "/#{@tree}/#{@branch}" if @tree

      FileUtils.mkdir_p(secret_dir_path)

      approx_size(ds)
      method(@format).call(ds)

      @size = File.size(file_path)
      ok
    end

    def on_save(db)
      db.prepared(
        'UPDATE snapshot_downloads SET size = ?, sha256sum = ? WHERE id = ?',
        @size / 1024 / 1024, @sum, @download_id
      )
    end

    def rollback
      begin
        File.unlink(file_path)
      rescue Errno::ENOENT
        # ignore
      end

      begin
        Dir.rmdir(secret_dir_path)
      rescue Errno::ENOENT
        # ignore
      end

      ok
    end

    protected

    def approx_size(ds)
      size = 0

      if @from_snapshot
        stream = ZfsStream.new({
                                 pool: @pool_fs,
                                 tree: @tree,
                                 branch: @branch,
                                 dataset: @dataset_name
                               }, @snapshot, @from_snapshot)
        size = stream.size

      else
        size = zfs(
          :get, '-Hp -o value referenced', "#{ds}@#{@snapshot}"
        ).output.strip.to_i / 1024 / 1024
      end

      db = NodeCtld::Db.new
      db.prepared('UPDATE snapshot_downloads SET size = ? WHERE id = ?', size, @download_id)
      db.close
    end

    def archive(ds)
      dir = pool_mounted_download(@pool_fs, @download_id.to_s)

      FileUtils.mkdir_p(dir)

      begin
        # If the transaction is being restarted, e.g. after a crash, the snapshot
        # may already be mounted.
        syscmd("mount -t zfs #{ds}@#{@snapshot} \"#{dir}\"") unless Pathname.new(dir).mountpoint?

        pipe_cmd("tar -cz -C \"#{dir}\" .")
      ensure
        10.times do
          st = syscmd("umount \"#{dir}\"", valid_rcs: [32])

          if [0, 32].include?(st.exitstatus)
            Dir.rmdir(dir)
            return
          end

          sleep(1)
        end

        raise "unable to unmount #{dir}"
      end
    end

    def stream(ds)
      pipe_cmd("zfs send #{ds}@#{@snapshot} | gzip")
    end

    def incremental_stream(ds)
      pipe_cmd("zfs send -I @#{@from_snapshot} #{ds}@#{@snapshot} | gzip")
    end

    def secret_dir_path
      "/#{@pool_fs}/#{path_to_pool_working_dir(:download)}/#{@secret_key}"
    end

    def file_path
      "#{secret_dir_path}/#{@file_name}"
    end

    def pipe_cmd(cmd)
      self.step = cmd

      digest = Digest::SHA256.new
      f = File.open(file_path, 'w')
      r, w = IO.pipe

      pid = Process.fork do
        r.close
        $stdout.reopen(w)
        Process.exec(cmd)
      end

      w.close

      until r.eof?
        data = r.read(131_072)
        digest << data
        f.write(data)
      end

      f.close
      @sum = digest.hexdigest

      Process.wait(pid)

      return unless $?.exitstatus != 0

      raise SystemCommandFailed.new(cmd, $?.exitstatus, '')
    end
  end
end
