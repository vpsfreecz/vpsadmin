module VpsAdmin::DownloadMounter
  class Mounter
    def initialize(opts, mountpoint, pool)
      @opts = opts
      @full_mnt = File.join(
        mountpoint,
        pool.node.domain_name + '.' + pool.node.location.environment.domain,
        pool.filesystem.split('/').last
      )
      @pool = pool
    end

    def mount
      # FIXME: this assumes that the pool is mounted to /<pool_name>
      src = "#{@pool.node.ip_addr}:/#{@pool.filesystem}/vpsadmin/download"

      if mountpoint_exists?
        puts "  mountpoint found"

      else
        puts "  creating mountpoint"
        FileUtils.mkpath(@full_mnt) unless @opts[:dry_run]
      end

      if mounted?
        puts "  is mounted"

      else
        run("mount -t nfs -overs=3 #{src} #{@full_mnt}")
      end
    end

    def umount
      if mounted?
        run("umount -f #{@full_mnt}")

      else
        puts "  not mounted"
      end
    end

    def mounted?
      Pathname.new(@full_mnt).mountpoint?
    end

    def mountpoint_exists?
      Dir.exists?(@full_mnt)
    end

    def run(cmd)
      puts "  #{cmd}"
      `#{cmd}` unless @opts[:dry_run]
    end
  end
end
