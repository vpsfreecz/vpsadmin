module VpsAdmind
  class Commands::Vps::IpAdd < Commands::Base
    handle 2006

    def exec
      VpsAdmind::Firewall.ip_map.set(@addr, @id, @user_id) if @register
      Vps.new(@vps_id).ip_add(@addr, @version, @register, @shaper)
      ok
    end

    def rollback
      Vps.new(@vps_id).ip_del(@addr, @version, @register, @shaper)
      VpsAdmind::Firewall.ip_map.unset(@addr) if @register
      ok
    end
  end
end
