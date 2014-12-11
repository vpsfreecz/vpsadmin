module VpsAdmind
  class Commands::Vps::IpAdd < Commands::Base
    handle 2006

    def exec
      Vps.new(@vps_id).ip_add(@addr, @version, @shaper)
    end
  end
end
