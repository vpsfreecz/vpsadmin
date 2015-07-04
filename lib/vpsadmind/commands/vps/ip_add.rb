module VpsAdmind
  class Commands::Vps::IpAdd < Commands::Base
    handle 2006

    def exec
      Vps.new(@vps_id).ip_add(@addr, @version, @register, @shaper)
    end

    def rollback
      Vps.new(@vps_id).ip_del(@addr, @version, @register, @shaper)
    end
  end
end
