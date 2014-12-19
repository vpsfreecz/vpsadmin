module VpsAdmind
  class Commands::Vps::Umount < Commands::Base
    handle 5303
    needs :system, :vz, :vps, :zfs

    def exec
      return ok unless status[:running]

      @mounts.each do |mnt|
        case mnt['type']
          when 'zfs'
            # Accept return code 1 - not mounted
            zfs(:umount, '-f', "#{mnt['pool_fs']}/#{mnt['dataset']}", [1])

          else
            runscript('preumount', mnt['preumount']) if @runscripts.nil? || @runscripts
            syscmd("#{$CFG.get(:bin, :umount)} #{mnt['umount_opts']} #{ve_root}/#{mnt['dst']}")
            runscript('postumount', mnt['postumount']) if @runscripts.nil? || @runscripts
        end
      end

      ok
    end

    def rollback
      call_cmd(Commands::Vps::Mount, {
          :mounts => @mounts.reverse,
          :runscripts => false
      })
    end
  end
end
