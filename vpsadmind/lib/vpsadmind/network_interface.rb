module VpsAdmind
  class NetworkInterface
    include Utils::Log
    include Utils::System
    include Utils::Vz

    def initialize(vps_id, name)
      @vps_id = vps_id
      @name = name
    end

    def add_route(addr, prefix, v, register, shaper)
      if register
        Shaper.new.shape_set(addr, prefix, v, shaper)
        Firewall.accounting.reg_ip(addr, prefix, v)
      end
    end

    def del_route(addr, prefix, v, unregister, shaper)
      if unregister
        Shaper.new.shape_unset(addr, prefix, v, shaper)
        Firewall.accounting.unreg_ip(addr, prefix, v)
      end
    end

    def add_host_addr(addr, prefix)
      vzctl(:set, @vps_id, {ipadd: addr}, true)
    end

    def del_host_addr(addr, prefix)
      vzctl(:set, @vps_id, {ipdel: addr}, true)
    end
  end
end
