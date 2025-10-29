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

    def enable
      cfg = VpsConfig.open(@vps_id)

      netif = cfg.network_interfaces[@guest_name]
      netif.enable = true

      cfg.save

      return unless @domain.active?

      syscmd("ip link set dev #{@host_name} up")

      netif.routes.each do |ip_v, routes|
        routes.each do |r|
          syscmd("ip -#{ip_v} route add #{r.address} #{r.via && "via #{r.via}"} dev #{@host_name}")
        end
      end
    end

    def disable
      VpsConfig.edit(@vps_id) do |cfg|
        cfg.network_interfaces[@guest_name].enable = false
      end

      return unless @domain.active?

      syscmd("ip link set dev #{@host_name} down")
    end

    def set_shaper(max_tx, max_rx)
      VpsConfig.edit(@vps_id) do |cfg|
        netif = cfg.network_interfaces[@guest_name]
        netif.max_tx = max_tx
        netif.max_rx = max_rx
      end

      @domain.interface_parameters = [
        @host_name,
        {
          'inbound.average' => max_rx / 1024 / 8,
          'inbound.peak' => (max_rx * 1.2 / 1024 / 8).round,
          'inbound.burst' => (max_rx * 1.05 / 1024 / 8).round,
          'outbound.average' => max_tx / 1024 / 8,
          'outbound.peak' => (max_tx * 1.2 / 1024 / 8).round,
          'outbound.burst' => (max_tx * 1.05 / 1024 / 8).round
        },
        Libvirt::Domain::AFFECT_LIVE | Libvirt::Domain::AFFECT_CONFIG
      ]
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
