module VpsAdmind
  class Commands::Vps::Mount < Commands::Base
    handle 5302
    needs :system, :vz, :vps, :zfs

    def exec
      return ok unless status[:running]

      @mounts.each do |mnt|
        case mnt['type']
          when 'zfs'
            zfs(:mount, nil, "#{mnt['pool_fs']}/#{mnt['dataset']}")

          else
            dst = "#{ve_root}/#{mnt['dst']}"

            unless File.exists?(dst)
              begin
                FileUtils.mkpath(dst)

              # it means, that the folder is mounted but was removed on the other end
              rescue Errno::EEXIST
                syscmd("#{$CFG.get(:bin, :umount)} -f #{dst}")
              end
            end

            runscript('premount', mnt['premount'])
            syscmd("#{$CFG.get(:bin, :mount)} #{mnt['mount_opts']} -o #{mnt['mode']} #{mnt['src']} #{dst}")
            runscript('postmount', mnt['postmount'])
        end
      end

      ok
    end
  end
end
