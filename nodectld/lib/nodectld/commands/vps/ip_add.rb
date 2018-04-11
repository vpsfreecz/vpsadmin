module NodeCtld
  class Commands::Vps::IpAdd < Commands::Base
    handle 2006

    def exec
      NodeCtld::Firewall.ip_map.set(@addr, @id, @version, @user_id) if @register
      Vps.new(@vps_id).ip_add(@veth_name, @addr, @version, @register, @shaper)
      ok
    end

    def rollback
      Vps.new(@vps_id).ip_del(@veth_name, @addr, @version, @register, @shaper)
      NodeCtld::Firewall.ip_map.unset(@addr) if @register
      ok
    end
  end
end
