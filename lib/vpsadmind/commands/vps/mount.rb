module VpsAdmind
  class Commands::Vps::Mount < Commands::Base
    handle 5302
    needs :system, :vz, :vps, :zfs, :pool

    def exec
      return ok unless status[:running]

      @mounts.each do |mnt|
        dst = "#{ve_root}/#{mnt['dst']}"
        create_dst(dst)

        case mnt['type']
          when 'dataset_local'
            syscmd("#{$CFG.get(:bin, :mount)} #{mnt['mount_opts']} /#{mnt['pool_fs']}/#{mnt['dataset_name']}/private #{dst}")

          when 'dataset_remote'
            syscmd("#{$CFG.get(:bin, :mount)} #{mnt['mount_opts']} #{mnt['src_node_addr']}:/#{mnt['pool_fs']}/#{mnt['dataset_name']}/private #{dst}")

          when 'snapshot_local'
            syscmd("#{$CFG.get(:bin, :mount)} -t zfs #{mnt['pool_fs']}/#{mnt['dataset_name']}@#{mnt['snapshot']} #{dst}")

          when 'snapshot_remote'
            syscmd("#{$CFG.get(:bin, :mount)} #{mnt['mount_opts']} #{mnt['src_node_addr']}:/#{pool_mounted_snapshot(@pool_fs, @snapshot_id)} #{dst}")

          else
            runscript('premount', mnt['premount']) if mnt['runscripts']
            syscmd("#{$CFG.get(:bin, :mount)} #{mnt['mount_opts']} -o #{mnt['mode']} #{mnt['src']} #{dst}")
            runscript('postmount', mnt['postmount']) if mnt['runscripts']
        end
      end

      ok
    end

    def rollback
      call_cmd(Commands::Vps::Umount, {
          :mounts => @mounts.reverse,
          :runscripts => false
      })
    end

    protected
    def create_dst(dst)
      unless File.exists?(dst)
        begin
          FileUtils.mkpath(dst)

            # it means, that the folder is mounted but was removed on the other end
        rescue Errno::EEXIST
          syscmd("#{$CFG.get(:bin, :umount)} -f #{dst}")
        end
      end
    end
  end
end
