module VpsAdmind
  # Mounter takes care of mounting and umounting local/remote
  # datasets/snapshots to VPS.
  class Mounter
    include Utils::Log
    include Utils::System
    include Utils::Vps
    include Utils::Pool

    class << self
      def mount_all(vps_id, mounts, oneshot)
        mounter = new(vps_id)
        mounts.each { |mnt| mounter.mount(mnt, oneshot) }
      end

      def umount_all(vps_id, mounts)
        mounter = new(vps_id)
        mounts.each { |mnt| mounter.umount(mnt) }
      end
    end

    def initialize(vps_id)
      @vps_id = vps_id
    end

    def mount_cmd(mnt)
      dst = "#{ve_root}/#{mnt['dst']}"

      cmd = case mnt['type']
        when 'dataset_local'
          "#{$CFG.get(:bin, :mount)} #{mnt['mount_opts']} /#{mnt['pool_fs']}/#{mnt['dataset_name']}/private #{dst}"

        when 'dataset_remote'
          "#{$CFG.get(:bin, :mount)} #{mnt['mount_opts']} #{mnt['src_node_addr']}:/#{mnt['pool_fs']}/#{mnt['dataset_name']}/private #{dst}"

        when 'snapshot_local'
          "#{$CFG.get(:bin, :mount)} -t zfs #{mnt['pool_fs']}/#{mnt['dataset_name']}@#{mnt['snapshot']} #{dst}"

        when 'snapshot_remote'
          "#{$CFG.get(:bin, :mount)} #{mnt['mount_opts']} #{mnt['src_node_addr']}:/#{pool_mounted_snapshot(mnt['pool_fs'], mnt['snapshot_id'])}/private #{dst}"

        else
          fail "unknown mount type '#{mnt['type']}'"
      end

      [dst, cmd]
    end

    def mount(opts, oneshot)
      counter = 0
      dst, cmd = mount_cmd(opts)

      create_dst(dst)
      
      runscript('premount', opts['premount']) if opts['runscripts']

      begin
        syscmd(cmd)

      rescue CommandFailed => e
        if /is busy or already mounted/ =~ e.output
          log(:info, :mounter, 'Already mounted')

        else
          raise e if oneshot
   
          counter += 1
          wait = random_wait(counter)
          
          log(:warn, :mounter, "Mount failed, retrying in #{wait} seconds")
          sleep(wait)
          retry
        end
      end

      runscript('postmount', opts['postmount']) if opts['runscripts']
    end

    def umount_cmd(mnt)
      dst = "#{ve_root}/#{mnt['dst']}"
      [dst, "#{$CFG.get(:bin, :umount)} #{mnt['umount_opts']} #{dst}"]
    end

    def umount(opts)
      dst, cmd = umount_cmd(opts)

      runscript('preumount', opts['preumount']) if opts['runscripts']
      syscmd(cmd)
      runscript('postumount', opts['postumount']) if opts['runscripts']
    end
    
    protected
    def create_dst(dst)
      return if File.exists?(dst)
      FileUtils.mkpath(dst)

    rescue Errno::EEXIST
      # it means, that the folder is mounted but was removed on the other end
      syscmd("#{$CFG.get(:bin, :umount)} -f #{dst}")
    end

    def random_wait(counter)
      base = 10 + counter * 5
      base = 60 if base > 60

      r = 10 + counter * 10
      r = 240 if r > 240

      base + rand(r)
    end
  end
end
