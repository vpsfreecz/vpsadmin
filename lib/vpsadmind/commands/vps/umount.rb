module VpsAdmind
  class Commands::Vps::Umount < Commands::Base
    handle 5303
    needs :system, :vz, :vps, :zfs

    def exec
      return ok unless status[:running]

      @mounts.each do |mnt|
        runscript('preumount', mnt['preumount']) if mnt['runscripts']
        dst = "#{ve_root}/#{mnt['dst']}"

        begin
          syscmd("#{$CFG.get(:bin, :umount)} #{mnt['umount_opts']} #{dst}")

        rescue CommandFailed => e
          raise e if e.rc != 1 || /^umount: #{dst}: not mounted$/ !~ e.output
        end

        runscript('postumount', mnt['postumount']) if mnt['runscripts']
      end

      ok
    end

    def rollback
      call_cmd(Commands::Vps::Mount, {
          :vps_id => @vps_id,
          :mounts => @mounts.reverse,
          :runscripts => false
      })
    end
  end
end
