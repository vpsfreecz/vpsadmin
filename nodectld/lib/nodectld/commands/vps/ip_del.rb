module NodeCtld
  class Commands::Vps::IpDel < Commands::Base
    handle 2007
    needs :osctl

    def exec
      Vps.new(@vps_id).ip_del(@veth_name, @addr, @prefix, @version, @unregister, @shaper)
      NodeCtld::Firewall.ip_map.unset(@addr) if @unregister
      ok
    end

    def rollback
      NodeCtld::Firewall.ip_map.set(@addr, @prefix, @id, @version, @user_id) if @unregister
      Vps.new(@vps_id).ip_add(@veth_name, @addr, @prefix, @version, @unregister, @shaper)
      ok
    end
  end
end
