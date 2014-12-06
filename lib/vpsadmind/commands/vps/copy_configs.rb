module VpsAdmind
  class Commands::Vps::CopyConfigs < Commands::Base
    handle 4001

    include Utils::System
    include Utils::Vz

    def exec
      scp("#{@src_node_addr}:#{$CFG.get(:vz, :vz_conf)}/conf/#{@vps_id}.*", "#{$CFG.get(:vz, :vz_conf)}/conf/")

      vzctl(:set, @vps_id, {:onboot => 'no'}, true)
    end
  end
end
