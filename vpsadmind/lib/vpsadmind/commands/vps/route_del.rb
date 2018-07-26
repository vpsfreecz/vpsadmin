module VpsAdmind
  class Commands::Vps::RouteDel < Commands::Base
    handle 2007

    def exec
      Vps.new(@vps_id).route_del(@addr, @version, @unregister, @shaper)
      VpsAdmind::Firewall.ip_map.unset(@addr) if @unregister
      ok
    end

    def rollback
      VpsAdmind::Firewall.ip_map.set(@addr, @id, @version, @user_id) if @unregister
      Vps.new(@vps_id).route_add(@addr, @version, @unregister, @shaper)
      ok
    end
  end
end
