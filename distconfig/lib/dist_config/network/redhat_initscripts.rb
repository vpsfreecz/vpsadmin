require 'dist_config/network/base'
require 'dist_config/helpers/redhat'

module DistConfig
  # Configure network using RH style sysconfig with initscripts
  class Network::RedHatInitScripts < Network::Base
    include DistConfig::Helpers::RedHat

    def usable?
      Dir.exist?(File.join(rootfs, 'etc/sysconfig/network-scripts')) \
        && File.executable?(File.join(rootfs, 'etc/init.d/network'))
    end

    def configure(netifs)
      super

      set_params(
        File.join(rootfs, 'etc/sysconfig/network'),
        { 'NETWORKING' => 'yes' }
      )

      netifs.each do |netif|
        do_create_netif(netif)
      end
    end

    # Cleanup old config files
    def remove_netif(_netifs, netif)
      do_remove_netif(netif.name)
    end

    # Rename config files
    def rename_netif(_netifs, netif, old_name)
      do_remove_netif(old_name)
      do_create_netif(netif)
    end

    protected

    def do_create_netif(netif)
      tpl_base = File.join('network/redhat_initscripts')
      ct_base = File.join(rootfs, 'etc', 'sysconfig')
      ifcfg = File.join(ct_base, 'network-scripts', "ifcfg-#{netif.name}")

      return unless writable?(ifcfg)

      ErbTemplate.render_to_if_changed(
        File.join(tpl_base, netif.type.to_s, 'ifcfg'),
        { netif: },
        ifcfg
      )

      return unless netif.type == :routed

      netif.active_ip_versions.each do |ip_v|
        ErbTemplate.render_to_if_changed(
          File.join(tpl_base, netif.type.to_s, "route_v#{ip_v}"),
          { netif: },
          File.join(
            ct_base,
            'network-scripts',
            "route#{ip_v == 6 ? '6' : ''}-#{netif.name}"
          )
        )
      end
    end

    def do_remove_netif(name)
      base = File.join(rootfs, 'etc', 'sysconfig', 'network-scripts')
      files = [
        "ifcfg-#{name}",
        "route-#{name}",
        "route6-#{name}"
      ]

      files.each do |f|
        path = File.join(base, f)
        next if !File.exist?(path) || !writable?(path)

        File.unlink(path)
      end
    end
  end
end
