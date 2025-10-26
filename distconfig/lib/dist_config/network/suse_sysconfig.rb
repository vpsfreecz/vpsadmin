require 'dist_config/network/base'

module DistConfig
  # Configure SUSE style /etc/sysconfig for wicked
  class Network::SuseSysconfig < Network::Base
    def usable?
      Dir.exist?(File.join(rootfs, 'etc/sysconfig/network')) \
        && Dir.exist?(File.join(rootfs, 'etc/wicked'))
    end

    def configure(netifs)
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
      tpl_base = File.join('network', 'suse_sysconfig')
      ct_base = File.join(rootfs, 'etc', 'sysconfig')
      ifcfg = File.join(ct_base, 'network', "ifcfg-#{netif.name}")

      return unless writable?(ifcfg)

      ErbTemplate.render_to_if_changed(
        File.join(tpl_base, netif.type.to_s, 'ifcfg'),
        {
          netif:,
          all_ips: netif.active_ip_versions.inject([]) do |acc, ip_v|
            acc.concat(netif.ips(ip_v))
          end
        },
        ifcfg
      )

      ErbTemplate.render_to_if_changed(
        File.join(tpl_base, netif.type.to_s, 'ifroute'),
        { netif: },
        File.join(
          ct_base,
          'network',
          "ifroute-#{netif.name}"
        )
      )
    end

    def do_remove_netif(name)
      base = File.join(rootfs, 'etc', 'sysconfig', 'network')
      files = [
        "ifcfg-#{name}"
      ]

      files.each do |f|
        path = File.join(base, f)
        next if !File.exist?(path) || !writable?(path)

        File.unlink(path)
      end
    end
  end
end
