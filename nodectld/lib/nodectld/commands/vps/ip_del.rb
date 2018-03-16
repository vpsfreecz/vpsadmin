module NodeCtld
  class Commands::Vps::IpDel < Commands::Base
    handle 2007
    needs :osctl

    def exec
      Vps.new(@vps_id).ip_del(@addr, @version, @unregister, @shaper)
      NodeCtld::Firewall.ip_map.unset(@addr) if @unregister
      ok
    end

    def rollback
      NodeCtld::Firewall.ip_map.set(@addr, @id, @version, @user_id) if @unregister
      Vps.new(@vps_id).ip_add(@addr, @version, @unregister, @shaper)
      ok
    end
  end
end
