require 'dist_config'
require 'optparse'

module DistConfig
  class Cli
    def self.run
      # configure
      # hostname-set
      # hostname-unset
      # netif-add
      # netif-del
      # netif-rename
      # passwd

      new.run
    end

    def run
      options, cmd, args = parse_options
      exit_status = 0

      vps_config = VpsConfig.new(options[:vps_config])
      opts = {
        rootfs: options[:rootfs],
        ct: options[:ct],
        verbose: options[:verbose]
      }

      case cmd
      when 'lxc-setup'
        ctstartmenu = args[0]
        DistConfig.run(vps_config, :setup_lxc_container, kwargs: { ctstartmenu: }, opts:)
      when 'rootfs-mount'
        DistConfig.run(vps_config, :mount_rootfs, opts:)
      when 'start'
        DistConfig.run(vps_config, :start, opts:)
      when 'stop'
        mode, timeout = args
        DistConfig.run(vps_config, :stop, kwargs: { mode: mode.to_sym, timeout: timeout.to_i }, opts:)
      when 'network-setup'
        DistConfig.run(vps_config, :setup_network, opts:)
      when 'os-template-set'
        distribution, version, arch, variant = args
        DistConfig.run(
          vps_config,
          :set_os_template,
          kwargs: {
            distribution:,
            version:,
            arch:,
            variant:
          },
          opts:
        )
      when 'hostname-set'
        hostname = args[0]
        DistConfig.run(vps_config, :set_hostname, args: [hostname], opts:)
      when 'hostname-unset'
        DistConfig.run(vps_config, :unset_hostname, opts:)
      when 'netif-add'
        # TODO
      when 'netif-del'
        # TODO
      when 'netif-rename'
        netif, new_netif = args
        DistConfig.run(vps_config, :rename_netif, args: [netif, new_netif], opts:)
      when 'hostaddr-add'
        netif, addr, prefix = args
        DistConfig.run(vps_config, :add_host_addr, args: [netif, addr, prefix], opts:)
      when 'hostaddr-del'
        netif, addr, prefix = args
        DistConfig.run(vps_config, :remove_host_addr, args: [netif, addr, prefix], opts:)
      when 'dns-resolvers-set'
        DistConfig.run(vps_config, :set_dns_resolvers, args: [args], opts:)
      when 'dns-resolvers-unset'
        DistConfig.run(vps_config, :unset_dns_resolvers, opts:)
      when 'passwd'
        user = args[0]
        password = $stdin.read.strip

        DistConfig.run(vps_config, :passwd, args: [user, password], opts:)
      when 'authorized-key-add'
        public_key = $stdin.read.strip
        DistConfig.run(vps_config, :add_authorized_key, args: [public_key], opts:)
      when 'authorized-key-del'
        public_key = $stdin.read.strip
        DistConfig.run(vps_config, :remove_authorized_key, args: [public_key], opts:)
      when 'runscript'
        result = DistConfig.run(vps_config, :runscript, args: [$stdin.read], opts:)

        exit_status = result.status
        $stdout.write(result.output)
      when 'rescue-system-warnings'
        mountpoint = args[0]
        DistConfig.run(vps_config, :add_rescue_system_warnings, args: [mountpoint], opts:)
      when 'user-script-install'
        content = $stdin.read
        DistConfig.run(vps_config, :install_user_script, args: [content], opts:)
      when 'cloud-init-install'
        result = DistConfig.run(vps_config, :install_cloud_init, opts:)

        exit_status = result.status
        $stdout.write(result.output)
      when 'cloud-init-deploy'
        format = args[0]
        content = $stdin.read
        DistConfig.run(vps_config, :deploy_cloud_init, args: [format, content], opts:)
      when 'nixos-config-apply'
        format = args[0]
        content = $stdin.read

        DistConfig.run(vps_config, :apply_nixos_config, args: [format, content], opts:)
      else
        warn "Unknown command #{cmd.inspect}"
        exit(false)
      end

      raise 'Failed to sync filesystem' unless system('sync')

      exit(exit_status)
    end

    protected

    def parse_options
      options = {
        vps_config: '/run/config/vpsadmin/config.json',
        rootfs: '/mnt/vps',
        ct: 'vps',
        verbose: true
      }

      parser = OptionParser.new do |opts|
        opts.banner = "Usage: #{$0} [options] <command> [arguments...]"

        opts.on('-c', '--config CONFIG', 'Path to VPS config') do |v|
          options[:vps_config] = v
        end

        opts.on('--rootfs PATH', 'Path to VPS root filesystem') do |v|
          options[:rootfs] = v
        end

        opts.on('--lxc-container NAME', 'Managed LXC container name') do |v|
          options[:ct] = v
        end

        opts.on('-v', '--verbose') do
          options[:verbose] = true
        end
      end

      args = parser.parse!

      if args.empty?
        warn 'Missing command'
        warn parser
        exit(false)
      end

      [options, args.first, args[1..]]
    end
  end
end
