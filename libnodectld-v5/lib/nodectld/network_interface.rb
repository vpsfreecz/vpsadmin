require 'ipaddress'

module NodeCtld
  class NetworkInterface
    include OsCtl::Lib::Utils::Log
    include Utils::System
    include Utils::Libvirt

    def initialize(domain, host_name, guest_name)
      @domain = domain
      @vps_id = domain.name
      @host_name = host_name
      @guest_name = guest_name
    end

    def add_route(addr, prefix, v, _register, via: nil)
      VpsConfig.edit(@vps_id) do |cfg|
        cfg.network_interfaces[@guest_name].add_route(config_route(addr, prefix, via))
        ConfigDrive.create(@vps_id, cfg)
      end

      return unless @domain.active?

      if via
        syscmd("ip -#{v} route add #{addr}/#{prefix} via #{via} dev #{@host_name}")
      else
        syscmd("ip -#{v} route add #{addr}/#{prefix} dev #{@host_name}")
      end
    end

    def del_route(addr, prefix, v, _unregister)
      VpsConfig.edit(@vps_id) do |cfg|
        cfg.network_interfaces[@guest_name].remove_route(config_route(addr, prefix, nil))
        ConfigDrive.create(@vps_id, cfg)
      end

      return unless @domain.active?

      syscmd("ip -#{v} route del #{addr}/#{prefix} dev #{@host_name}")
    end

    def add_host_addr(addr, prefix, v)
      VpsConfig.edit(@vps_id) do |cfg|
        cfg.network_interfaces[@guest_name].add_ip(v, "#{addr}/#{prefix}")
        ConfigDrive.create(@vps_id, cfg)
      end

      return unless @domain.active?

      distconfig!(@domain, ['hostaddr-add', @guest_name, addr, prefix])
    end

    def del_host_addr(addr, prefix, v)
      VpsConfig.edit(@vps_id) do |cfg|
        cfg.network_interfaces[@guest_name].remove_ip(v, "#{addr}/#{prefix}")
        ConfigDrive.create(@vps_id, cfg)
      end

      return unless @domain.active?

      distconfig!(@domain, ['hostaddr-del', @guest_name, addr, prefix])
    end

    protected

    def config_route(addr, prefix, via)
      VpsConfig::Route.new(IPAddress.parse("#{addr}/#{prefix}"), via)
    end
  end
end
