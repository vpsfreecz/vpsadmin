module VpsAdmind
  class Node
    include Utils::System

    def init
      sharenfs = $CFG.get(:vps, :zfs, :sharenfs)

      unless sharenfs.nil?
        ds = $CFG.get(:vps, :zfs, :root_dataset)

        if syscmd("#{$CFG.get(:bin, :exportfs)}")[:output] =~ /^\/#{ds}\/\d+$/
          log "ZFS exports already loaded"
          return
        end

        log "Reload ZFS exports"
        zfs(:share, '-a', '')
      end
    end

    def load
      m = /load average\: (\d+\.\d+), (\d+\.\d+), (\d+\.\d+)/.match(syscmd($CFG.get(:bin, :uptime))[:output])

      if m
        {1 => m[1], 5 => m[2], 15 => m[3]}
      else
        {}
      end
    end

    def kernel
      syscmd("#{$CFG.get(:bin, :uname)} -r")[:output].strip
    end

    def conf_path(name = nil)
      "#{$CFG.get(:vz, :vz_conf)}/conf/ve-#{name}.conf-sample"
    end
  end
end
