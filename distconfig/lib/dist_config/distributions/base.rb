require 'dist_config/configurator'
require 'dist_config/helpers/log'
require 'json'

module DistConfig
  class Distributions::Base
    SYSTEM_PATH = %w[
      /bin
      /usr/bin
      /sbin
      /usr/sbin
      /run/current-system/sw/bin
      /nix/var/nix/profiles/system/sw/bin
      /run/current-system/profile/bin
      /run/current-system/profile/sbin
      /var/guix/profiles/system/profile/bin
      /var/guix/profiles/system/profile/sbin
    ].freeze

    CommandResult = Struct.new(:status, :output) do
      def success?
        status == 0
      end
    end

    def self.distribution(n = nil)
      if n
        DistConfig.register(n, self)
      else
        n
      end
    end

    SYS_CLASS_NET = '/sys/class/net'.freeze

    include Helpers::Log

    # @param vps_config [VpsConfig]
    # @param rootfs [String]
    # @param ct [String]
    # @param verbose [Boolean]
    def initialize(vps_config, rootfs:, ct:, verbose: false)
      @vps_config = vps_config
      @rootfs = rootfs
      @ct = ct
      @verbose = verbose
    end

    def configurator_class
      raise "define #{self.class}#configurator_class" unless self.class.const_defined?(:Configurator)

      cls = self.class::Configurator
      log(:debug, "Using #{cls} for #{vps_config.distribution}")
      cls
    end

    # Run just before the container is started
    def start
      return if !vps_config.hostname && vps_config.dns_resolvers.empty? && vps_config.network_interfaces.empty?

      setup_network_interfaces

      with_rootfs do
        if vps_config.hostname
          configurator.set_hostname(vps_config.hostname)
          configurator.update_etc_hosts(vps_config.hostname)
        end

        configurator.dns_resolvers(vps_config.dns_resolvers) if vps_config.dns_resolvers.any?

        network
        nil
      end
    end

    # Gracefully stop the container
    # @param mode [:stop, :shutdown, :kill]
    # @param timeout [Integer]
    def stop(mode: :stop, timeout: 300)
      cmd = ['lxc-stop', '-n', @ct, '--timeout', timeout.to_s]

      case mode
      when :stop
        # pass
      when :shutdown
        cmd << '--nokill'
      when :kill
        cmd << '--kill'
      else
        raise ArgumentError, "Unknown mode #{mode.inspect}"
      end

      return if system(*cmd)

      raise "#{mode} failed"
    end

    # Set container hostname
    # @param hostname [String]
    def set_hostname(hostname)
      old_hostname = vps_config.hostname

      vps_config.hostname = Hostname.new(hostname)
      vps_config.save

      with_rootfs do
        configurator.set_hostname(vps_config.hostname, old_hostname:)
        configurator.update_etc_hosts(vps_config.hostname, old_hostname:)
        nil
      end

      apply_hostname unless @within_rootfs
    end

    # Unset container hostname
    def unset_hostname
      vps_config.hostname = nil
      vps_config.save
    end

    # Configure hostname in a running system
    def apply_hostname
      log(:warn, "Unable to apply hostname on #{vps_config.distribution}: not implemented")
    end

    # Update hostname in `/etc/hosts`, optionally removing configuration of old
    # hostname.
    #
    # @param old_hostname [Hostname, nil]
    def update_etc_hosts(old_hostname: nil)
      with_rootfs do
        configurator.update_etc_hosts(vps_config.hostname, old_hostname:)
        nil
      end
    end

    # Remove the vpsAdmin-generated notice from /etc/hosts
    def unset_etc_hosts
      with_rootfs do
        configurator.unset_etc_hosts
        nil
      end
    end

    # Rename network interfaces to their configured name
    def setup_network_interfaces
      vps_config.network_interfaces.each do |netif|
        next if netif.guest_mac.nil?

        name = find_network_interface_by_mac(netif.guest_mac)

        if name.nil?
          log(:fatal, "Unable to find network interface #{netif.name} (#{netif.guest_mac})")
          next
        end

        next if name == netif.name
        next if system('ip', 'link', 'set', 'dev', name, 'name', netif.name)

        log(:warn, "Failed to rename network interface #{name.inspect} to #{netif.name}")
      end
    end

    def network
      with_rootfs do
        configurator.network(vps_config.network_interfaces)
        nil
      end
    end

    # Called when a new network interface is added to a container
    # @param netif [String]
    def add_netif(netif)
      with_rootfs do
        configurator.add_netif(vps_config.network_interfaces, netif)
        nil
      end
    end

    # Called when a network interface is removed from a container
    # @param netif [String]
    def remove_netif
      with_rootfs do
        configurator.remove_netif(vps_config.network_interfaces, netif)
        nil
      end
    end

    # Called when an existing network interface is renamed
    # @param netif [String]
    # @param original_name [String]
    def rename_netif(netif, original_name)
      with_rootfs do
        configurator.rename_netif(vps_config.network_interfaces, netif, original_name)
        nil
      end
    end

    # @param netif [String]
    # @param addr [String]
    # @param prefix [Integer]
    def add_host_addr(netif, addr, prefix)
      network_interface = vps_config.network_interfaces.detect { |n| n.guest_name == netif }
      raise "Network interface #{netif.inspect} not found" if network_interface.nil?

      ip = network_interface.add_ip(addr, prefix)
      vps_config.save

      ct_syscmd(
        %W[ip -#{ip.version} addr add #{ip.to_string} dev #{netif.guest_name}],
        valid_rcs: :all
      )
    end

    # @param netif [String]
    # @param addr [String]
    # @param prefix [Integer]
    def remove_host_addr(netif, addr, prefix)
      network_interface = vps_config.network_interfaces.detect { |n| n.guest_name == netif }
      raise "Network interface #{netif.inspect} not found" if network_interface.nil?

      ip = network_interface.remove_ip(addr, prefix)
      vps_config.save

      ct_syscmd(
        %W[ip -#{ip.version} addr del #{ip.to_string} dev #{netif.guest_name}],
        valid_rcs: :all
      )
    end

    # @param dns_resolvers [Array<String>]
    def set_dns_resolvers(dns_resolvers)
      vps_config.dns_resolvers = dns_resolvers
      vps_config.save

      with_rootfs do
        configurator.dns_resolvers(dns_resolvers)
        nil
      end
    end

    def unset_dns_resolvers
      vps_config.dns_resolvers = []
      vps_config.save
    end

    # @param user [String]
    # @param password [String]
    def passwd(user, password)
      ret = ct_syscmd(
        %w[chpasswd],
        stdin: "#{user}:#{password}\n",
        run: true,
        valid_rcs: :all
      )

      return true if ret.success?

      log(:warn, "Unable to set password: #{ret.output}")
    end

    # @param public_key [String]
    def add_authorized_key(public_key)
      with_rootfs do
        configurator.add_authorized_key(public_key)
        nil
      end
    end

    # @param public_key [String]
    def remove_authorized_key(public_key)
      with_rootfs do
        configurator.remove_authorized_key(public_key)
        nil
      end
    end

    # Return path to `/bin` or an alternative, where a shell is looked up
    # @return [String]
    def bin_path
      '/bin'
    end

    protected

    attr_reader :vps_config, :configurator

    # Execute code block while chrooted to container rootfs
    # @return [any] return value from the code block
    def with_rootfs(&block)
      return block.call if @within_rootfs

      r, w = IO.pipe

      pid = Process.fork do
        r.close

        Dir.chroot(@rootfs)

        @configurator = configurator_class.new(
          '/',
          vps_config.distribution,
          vps_config.version,
          verbose: @verbose
        )

        @within_rootfs = true

        w.puts({ return: block.call }.to_json)
        w.close
      end

      w.close
      ret = JSON.parse(r.read)
      r.close

      Process.wait(pid)
      ret['return']
    end

    def ct_syscmd(cmd, run: false, stdin: nil, valid_rcs: [0])
      lxc_cmd =
        if run && `lxc-info -n #{@ct} -s -H`.strip.downcase != 'running'
          'lxc-execute'
        else
          'lxc-attach'
        end

      out_r, out_w = IO.pipe

      spawn_kwargs = {
        out: out_w,
        err: out_w
      }

      if stdin
        in_r, in_w = IO.pipe
        spawn_kwargs[:in] = in_r
      end

      pid = Process.spawn(
        lxc_cmd,
        '-n', @ct,
        '-v', "PATH=#{SYSTEM_PATH.join(':')}",
        '--',
        *cmd,
        **spawn_kwargs
      )

      out_w.close

      if stdin
        in_r.close
        in_w.write(stdin)
        in_w.close
      end

      output = out_r.read
      out_r.close

      Process.wait(pid)

      status = $?.exitstatus

      if valid_rcs != :all && !valid_rcs.include?(status)
        raise SystemCommandFailed.new(cmd.join(' '), status, output)
      end

      CommandResult.new(status, output)
    end

    # Check if the container is using systemd as init
    #
    # This method accesses the container's rootfs from the host, which is
    # dangerous because of symlinks and we really shouldn't be doing it... but
    # in this case, we only do readlink(), so it shouldn't do any harm.
    #
    # @return [Boolean]
    def volatile_is_systemd?
      return true if vps_config.distribution == 'nixos'

      begin
        File.readlink(File.join(@rootfs, 'sbin/init')).include?('systemd')
      rescue SystemCallError
        false
      end
    end

    def find_network_interface_by_mac(mac)
      Dir.entries(SYS_CLASS_NET).each do |ifname|
        next if %w[. ..].include?(ifname)

        addr_path = File.join(SYS_CLASS_NET, ifname, 'address')
        next unless File.file?(addr_path)

        return ifname if File.read(addr_path).strip == mac
      end

      nil
    end
  end
end
