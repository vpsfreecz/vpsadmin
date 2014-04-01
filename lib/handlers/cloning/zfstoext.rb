require 'lib/handlers/clone'

module CloneBackend
  class ZfsToExtClone < Clone
    def remote_clone
      copy_config
      create_root

      rsync([:vps, :clone, :rsync], {
          :src => "#{@params["src_addr"]}:#{$CFG.get(:vz, :vz_root)}/private/#{@params["src_veid"]}/private/",
          :dst => "#{$CFG.get(:vz, :vz_root)}/private/#{@veid}",
      })

      vzctl(:set, @veid, {:root => @new_vps.ve_root, :private => @new_vps.ve_private}, true)
      del_ips
    end
  end
end
