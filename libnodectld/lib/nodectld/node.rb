require 'libosctl'
require 'nodectld/utils'

module NodeCtld
  class Node
    include OsCtl::Lib::Utils::Log
    include Utils::System
    include Utils::Zfs

    def init
      sharenfs = $CFG.get(:vps, :zfs, :sharenfs)

      unless sharenfs.nil?
        ds = $CFG.get(:vps, :zfs, :root_dataset)

        if syscmd("#{$CFG.get(:bin, :exportfs)}").output =~ /^\/#{ds}\/\d+$/
          log "ZFS exports already loaded"
          return
        end

        log "Reload ZFS exports"
        zfs(:share, '-a', '')
      end
    end
  end
end
