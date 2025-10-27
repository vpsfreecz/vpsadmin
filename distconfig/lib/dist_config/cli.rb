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

      vps_config = VpsConfig.new(options[:vps_config])
      cmd_opts = {
        rootfs: options[:rootfs],
        ct: options[:ct],
        verbose: options[:verbose]
      }

      case cmd
      when 'start'
        DistConfig.run(vps_config, :start, {}, **cmd_opts)
      when 'stop'
        mode, timeout = args
        DistConfig.run(vps_config, :stop, { mode: mode.to_sym, timeout: timeout.to_i }, **cmd_opts)
      when 'hostname-set'
        unless [0, 1].include?(args.length)
          warn 'Usage: '
          exit(false)
        end

        old_hostname = args.first
        DistConfig.run(vps_config, :set_hostname, { original: old_hostname }, **cmd_opts)
      when 'netif-add'
        # TODO
      when 'netif-del'
        # TODO
      when 'netif-rename'
        # TODO
      when 'hostaddr-add'
        netif, addr, prefix = args
        DistConfig.run(vps_config, :add_host_addr, { netif:, addr:, prefix: }, **cmd_opts)
      when 'hostaddr-del'
        netif, addr, prefix = args
        DistConfig.run(vps_config, :remove_host_addr, { netif:, addr:, prefix: }, **cmd_opts)
      when 'passwd'
        user = args[0]
        password = $stdin.read.strip

        DistConfig.run(vps_config, :passwd, { user:, password: }, **cmd_opts)
      when 'authorized-key-add'
        public_key = $stdin.read.strip
        DistConfig.run(vps_config, :add_authorized_key, { public_key: }, **cmd_opts)
      when 'authorized-key-del'
        public_key = $stdin.read.strip
        DistConfig.run(vps_config, :remove_authorized_key, { public_key: }, **cmd_opts)
      else
        warn "Unknown command #{cmd.inspect}"
        exit(false)
      end
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
