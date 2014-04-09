require 'lib/handlers/clone'
require 'lib/utils/zfs'

module CloneBackend
  class ExtToZfsClone < Clone
    include ZfsUtils

    def remote_clone
      copy_config
      create_root

      zfs(:create, nil, @new_vps.ve_private_ds)

      rsync([:vps, :clone, :rsync], {
          :src => "#{@params["src_addr"]}:#{$CFG.get(:vz, :vz_root)}/private/#{@params["src_veid"]}/",
          :dst => @new_vps.ve_private,
      })

      vzctl(:set, @veid, {:root => @new_vps.ve_root, :private => @new_vps.ve_private}, true)
      del_ips
    end
  end
end
