require 'dist_config/configurator'
require 'dist_config/helpers/log'
require 'fileutils'
require 'json'
require 'tempfile'

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

    def setup_lxc_container(ctstartmenu:)
      lxc_dir = '/var/lib/lxc/vps'
      hooks = %w[pre-start post-stop].to_h do |hook|
        [hook, File.join(lxc_dir, hook)]
      end

      kernel_modules_ct_dir = with_rootfs do
        modules_dir = '/lib/modules'

        begin
          File.realpath(modules_dir)
        rescue Errno::ENOENT
          modules_dir
        end
      end

      kernel_modules_ct_dir = kernel_modules_ct_dir[1..] while kernel_modules_ct_dir.start_with?('/')

      rescue_rootfs_mountpoint = vps_config.rescue_rootfs_mountpoint
      rescue_rootfs_mountpoint = rescue_rootfs_mountpoint[1..] while rescue_rootfs_mountpoint && rescue_rootfs_mountpoint.start_with?('/')

      vars = {
        lxc_dir:,
        hostname: vps_config.hostname || vps_config.vps_id.to_s,
        init_cmd: vps_config.init_cmd,
        kernel_modules_host_dir: File.realpath('/run/current-system/kernel-modules/lib/modules'),
        kernel_modules_ct_dir:,
        rescue_label: vps_config.rescue_label,
        rescue_rootfs_mountpoint:,
        hooks:
      }

      if vps_config.start_menu_timeout > 0
        FileUtils.mkdir_p('/dev/.vpsadmin')
        FileUtils.cp(File.join(ctstartmenu, 'bin/ctstartmenu'), '/dev/.vpsadmin/ctstartmenu')
        File.chmod(0o755, '/dev/.vpsadmin/ctstartmenu')
        vars[:init_cmd] = "/dev/.vpsadmin/ctstartmenu -timeout #{vps_config.start_menu_timeout} #{vars[:init_cmd]}"
      end

      FileUtils.mkdir_p(lxc_dir)
      ErbTemplate.render_to('lxc/config', vars, File.join(lxc_dir, 'config'))

      hooks.each do |hook, path|
        ErbTemplate.render_to("lxc/#{hook}", {}, path, perm: 0o755)
      end
    end

    def mount_rootfs
      FileUtils.mkdir_p('/mnt/vps')

      options = []

      options << if rootfs_type == 'btrfs'
                   'subvol=@'
                 else
                   'defaults'
                 end

      str_options = options.join(',')

      if vps_config.rescue_label
        puts 'Mounting rescue system'

        unless system('mount', '-o', str_options, "/dev/disk/by-label/#{vps_config.rescue_label}", '/mnt/vps')
          raise 'Failed to mount rescue system'
        end

        if vps_config.rescue_rootfs_mountpoint
          FileUtils.mkdir_p('/mnt/rootfs')
          puts 'Mounting container rootfs'

          unless system('mount', '-o', str_options, "/dev/disk/by-label/#{vps_config.rootfs_label}", '/mnt/rootfs')
            raise 'Failed to mount rootfs'
          end
        end

      else
        puts 'Mounting container rootfs'

        unless system('mount', '-o', str_options, "/dev/disk/by-label/#{vps_config.rootfs_label}", '/mnt/vps')
          raise 'Failed to mount rootfs'
        end
      end
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

    def set_os_template(distribution:, version:, arch:, variant:)
      vps_config.distribution = distribution
      vps_config.version = version
      vps_config.arch = arch
      vps_config.variant = variant
      vps_config.save
      nil
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
    # @param new_guest_name [String]
    def rename_netif(netif, new_guest_name)
      network_interface = vps_config.network_interfaces.detect { |n| n.guest_name == netif }
      raise "Network interface #{netif.inspect} not found" if network_interface.nil?

      old_guest_name = network_interface.guest_name
      network_interface.guest_name = new_guest_name
      vps_config.save

      with_rootfs do
        configurator.rename_netif(vps_config.network_interfaces, network_interface, old_guest_name)
        nil
      end

      return if system('ip', 'link', 'set', 'dev', old_guest_name, 'name', network_interface.guest_name)

      log(:warn, "Failed to rename network interface #{old_guest_name.inspect} to #{new_guest_name.inspect}")
      nil
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

    def setup_network
      setup_network_interfaces

      vps_config.network_interfaces.each do |netif|
        syscmd("ip link set #{netif.guest_name} up")

        netif.active_ip_versions.each do |ip_v|
          netif.ips(ip_v).each do |ip|
            syscmd("ip -#{ip_v} addr add #{ip.to_string} dev #{netif.guest_name}")
          end

          gw = netif.default_via(ip_v)

          syscmd("ip route add #{gw} dev #{netif.guest_name}")
          syscmd("ip route add default via #{gw} dev #{netif.guest_name}")
        end
      end
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

    # @param script [String]
    # @return [CommandResult]
    def runscript(script, run: true, valid_rcs: [0])
      tmp = Tempfile.new('.distconfig-runscript', @rootfs)
      tmp.write(script)
      tmp.close

      File.chmod(0o700, tmp.path)

      begin
        result = ct_syscmd([File.join('/', File.basename(tmp.path))], run:, valid_rcs:)
      ensure
        tmp.unlink
      end

      result
    end

    # @param mountpoint [String]
    def add_rescue_system_warnings(mountpoint)
      with_rootfs do
        configurator.add_rescue_system_warnings(mountpoint)
        nil
      end
    end

    # @param content [String]
    def install_user_script(content)
      with_rootfs do
        configurator.install_user_script(content)
        nil
      end
    end

    # @return [CommandResult]
    def install_cloud_init
      commands = install_cloud_init_commands
      commands = commands.join("\n\n") if commands.is_a?(Array)

      script = <<~END
        #!/bin/sh
        set -e

        #{commands}

        # Disable network configuration, so that cloud-init doesn't break
        # already existing network configuration. vendor-data doesn't seem to work,
        # so putting it to /etc.
        mkdir -p /etc/cloud/cloud.cfg.d
        echo "network: {config: disabled}" > /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
      END

      runscript(script, run: true)
    end

    def deploy_cloud_init(format, content)
      with_rootfs do
        configurator.deploy_cloud_init(format, content)
      end
    end

    # @return [String, Array<String>]
    def install_cloud_init_commands
      raise NotImplementedError
    end

    # @param type [String]
    # @param content [String]
    def apply_nixos_config(type, content)
      raise NotImplementedError
    end

    # Return path to `/bin` or an alternative, where a shell is looked up
    # @return [String]
    def bin_path
      '/bin'
    end

    protected

    attr_reader :vps_config, :configurator

    def rootfs_type
      ret = `blkid -o value -s TYPE /dev/disk/by-label/#{vps_config.rootfs_label}`.strip
      raise "Unable to get rootfs type, blkid exited with #{$?.exitstatus}" if $?.exitstatus > 0

      ret
    end

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
          vps_config,
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
          [
            'lxc-execute',
            '-n', @ct,
            '-s', 'lxc.environment=PATH',
            '--',
            *cmd
          ]
        else
          [
            'lxc-attach',
            '-n', @ct,
            '-v', "PATH=#{SYSTEM_PATH.join(':')}",
            '--',
            *cmd
          ]
        end

      syscmd(lxc_cmd, stdin:, valid_rcs:)
    end

    def syscmd(cmd, stdin: nil, valid_rcs: [0])
      out_r, out_w = IO.pipe

      spawn_kwargs = {
        out: out_w,
        err: out_w
      }

      if stdin
        in_r, in_w = IO.pipe
        spawn_kwargs[:in] = in_r
      end

      pid = Process.spawn({ 'PATH' => SYSTEM_PATH.join(':') }, *cmd, **spawn_kwargs)

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
