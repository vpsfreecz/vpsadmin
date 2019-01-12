require 'digest'

module VpsAdmind
  class Commands::Dataset::DownloadSnapshot < Commands::Base
    handle 5004
    needs :system, :zfs, :pool

    def exec
      ds = "#{@pool_fs}/#{@dataset_name}"
      ds += "/#{@tree}/#{@branch}" if @tree

      syscmd("#{$CFG.get(:bin, :mkdir)} \"#{secret_dir_path}\"")

      approx_size(ds)
      method(@format).call(ds)

      ok(
        size: File.size(file_path),
        sha256sum: @sum,
      )
    end

    def rollback
      syscmd("#{$CFG.get(:bin, :rm)} -f \"#{file_path}\"") if File.exists?(file_path)
      syscmd("#{$CFG.get(:bin, :rmdir)} \"#{secret_dir_path}\"") if File.exists?(secret_dir_path)
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
            dataset: @dataset_name,
        }, @snapshot, @from_snapshot)
        size = stream.size

      else
        size = zfs(
            :get, '-Hp -o value referenced', "#{ds}@#{@snapshot}"
        )[:output].strip.to_i / 1024 / 1024
      end

      db = VpsAdmind::Db.new
      db.prepared('UPDATE snapshot_downloads SET size = ? WHERE id = ?', size, @download_id)
      db.close
    end

    def archive(ds)
      # On ZoL, snapshots in .zfs are mounted using automounts, so for tar
      # to work properly, it must be accessed before, so that it is already mounted
      # when tar is launched.
      Dir.entries("/#{ds}/.zfs/snapshot/#{@snapshot}")

      pipe_cmd("tar -cz -C \"/#{ds}/.zfs/snapshot\" \"#{@snapshot}\"")
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
        STDOUT.reopen(w)
        Process.exec(cmd)
      end

      w.close

      until r.eof?
        data = r.read(131072)
        digest << data
        f.write(data)
      end

      f.close
      @sum = digest.hexdigest

      Process.wait(pid)

      if $?.exitstatus != 0
        raise SystemCommandFailed.new(cmd, $?.exitstatus, '')
      end
    end
  end
end
