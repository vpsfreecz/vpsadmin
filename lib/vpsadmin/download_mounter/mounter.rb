module VpsAdmin::DownloadMounter
  class Mounter
    def initialize(opts, mountpoint, pool)
      @opts = opts
      @full_mnt = File.join(
          mountpoint,
          pool.node.domain_name + '.' + pool.node.environment.domain,
          pool.filesystem.split('/').last
      )
      @pool = pool
    end

    def mount
      # FIXME: this assumes that the pool is mounted to /<pool_name>
      src = "#{@pool.node.ip_addr}:/#{@pool.filesystem}/vpsadmin/download"

      if Dir.exists?(@full_mnt)
        puts "  mountpoint found"

      else
        puts "  creating mountpoint"
        FileUtils.mkpath(@full_mnt) unless @opts[:dry_run]
      end

      p = Pathname.new(@full_mnt)

      if p.mountpoint?
        puts "  is mounted"

      else
        cmd = "mount -t nfs -overs=3 #{src} #{@full_mnt}"
        puts "  #{cmd}"
        `#{cmd}` unless @opts[:dry_run]
      end
    end
  end
end
