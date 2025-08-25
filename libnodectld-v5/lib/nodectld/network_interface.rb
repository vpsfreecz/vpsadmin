require 'ipaddress'

module NodeCtld
  class NetworkInterface
    include OsCtl::Lib::Utils::Log
    include Utils::System
    include Utils::OsCtl

    def initialize(pool_fs, vps_id, name)
      @pool_fs = pool_fs
      @vps_id = vps_id
      @name = name
    end

    def add_route(addr, prefix, _v, _register, via: nil)
      VpsConfig.edit(@pool_fs, @vps_id) do |cfg|
        cfg.network_interfaces[@name].add_route(config_route(
                                                  addr, prefix, via
                                                ))
      end

      opts = {}
      opts[:via] = via if via

      osctl(%i[ct netif route add], [@vps_id, @name, "#{addr}/#{prefix}"], opts)
    end

    def del_route(addr, prefix, _v, _unregister)
      VpsConfig.edit(@pool_fs, @vps_id) do |cfg|
        cfg.network_interfaces[@name].remove_route(config_route(
                                                     addr, prefix, nil
                                                   ))
      end

      osctl(%i[ct netif route del], [@vps_id, @name, "#{addr}/#{prefix}"])
    end

    def add_host_addr(addr, prefix)
      osctl(
        %i[ct netif ip add],
        [@vps_id, @name, "#{addr}/#{prefix}"],
        { no_route: true }
      )
    end

    def del_host_addr(addr, prefix)
      osctl(
        %i[ct netif ip del],
        [@vps_id, @name, "#{addr}/#{prefix}"],
        { keep_route: true }
      )
    end

    protected

    def config_route(addr, prefix, via)
      VpsConfig::Route.new(IPAddress.parse("#{addr}/#{prefix}"), via)
    end
  end
end
