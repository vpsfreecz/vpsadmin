module VpsAdmind
  class Node
    include Utils::Log
    include Utils::System
    include Utils::Zfs

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

    def conf_path(name = nil)
      "#{$CFG.get(:vz, :vz_conf)}/conf/ve-#{name}.conf-sample"
    end
  end
end
