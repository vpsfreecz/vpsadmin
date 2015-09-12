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
          if e.rc != 1 || /^umount: #{dst}: not mounted$/ !~ e.output
            @skip_rollback = /^umount2: Device or resource busy$/ =~ e.output

            raise e
          end
        end

        runscript('postumount', mnt['postumount']) if mnt['runscripts']
      end

      ok
    end

    def rollback
      if @skip_rollback
        log(:debug, self, 'Skipping rollback of Vps::Umount')
        ok

      else
        call_cmd(Commands::Vps::Mount, {
            :vps_id => @vps_id,
            :mounts => @mounts.reverse,
            :runscripts => false
        })
      end
    end
  end
end
