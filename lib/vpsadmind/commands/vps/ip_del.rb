module VpsAdmind
  class Commands::Vps::IpDel < Commands::Base
    handle 2007

    def exec
      Vps.new(@vps_id).ip_del(@addr, @version, @shaper)
    end
  end
end
