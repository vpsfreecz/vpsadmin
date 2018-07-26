module NodeCtld
  class NetworkInterface
    include OsCtl::Lib::Utils::Log
    include Utils::System
    include Utils::OsCtl

    def initialize(vps_id, name)
      @vps_id = vps_id
      @name = name
    end

    def add_route(addr, prefix, v, register, shaper)
      if register
        Shaper.add_ip(
          @vps_id,
          netif: @name,
          addr: addr,
          prefix: prefix,
          version: v,
          class_id: shaper['class_id'],
          max_tx: shaper['max_tx'],
          max_rx: shaper['max_rx'],
        )
        Firewall.accounting.reg_ip(addr, prefix, v)
      end

      osctl(%i(ct netif route add), [@vps_id, @name, "#{addr}/#{prefix}"])
    end

    def del_route(addr, prefix, v, unregister, shaper)
      if unregister
        Shaper.remove_ip(
          @vps_id,
          netif: @name,
          addr: addr,
          prefix: prefix,
          version: v,
          class_id: shaper['class_id'],
        )
        Firewall.accounting.unreg_ip(addr, prefix, v)
      end

      osctl(%i(ct netif route del), [@vps_id, @name, "#{addr}/#{prefix}"])
    end
  end
end
