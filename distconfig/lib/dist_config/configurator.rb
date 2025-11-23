require 'dist_config/helpers/common'
require 'dist_config/helpers/file'
require 'dist_config/helpers/log'

module DistConfig
  # Base class for per-distribution configurators
  #
  # Configurators are used to manipulate the container's root filesystem. It is
  # called from a forked process with a container-specific mount namespace.
  class Configurator
    include Helpers::Log
    include Helpers::Common
    include Helpers::File

    # @return [String]
    attr_reader :rootfs

    # @return [VpsConfig]
    attr_reader :vps_config

    # @return [String]
    attr_reader :distribution

    # @return [String]
    attr_reader :version

    # @param rootfs [String]
    # @param vps_config [VpsConfig]
    # @param verbose [Boolean]
    def initialize(rootfs, vps_config, verbose: false)
      @rootfs = rootfs
      @vps_config = vps_config
      @distribution = vps_config.distribution
      @version = vps_config.version
      @verbose = verbose
      @network_backend = instantiate_network_class
    end

    # @param new_hostname [Hostname]
    # @param old_hostname [Hostname, nil]
    def set_hostname(new_hostname, old_hostname: nil)
      raise NotImplementedError
    end

    # @param new_hostname [Hostname]
    # @param old_hostname [Hostname, nil]
    def update_etc_hosts(new_hostname, old_hostname: nil)
      path = File.join(rootfs, 'etc', 'hosts')
      return unless writable?(path)

      hosts = EtcHosts.new(path)

      if old_hostname
        hosts.replace(old_hostname, new_hostname)
      else
        hosts.set(new_hostname)
      end
    end

    def unset_etc_hosts
      path = File.join(rootfs, 'etc', 'hosts')
      return unless writable?(path)

      hosts = EtcHosts.new(path)
      hosts.unmanage
    end

    # Configure networking
    # @param netifs [Array<NetworkInterface>]
    def network(netifs)
      network_backend && network_backend.configure(netifs)
    end

    # Called when a new network interface is added to a container
    # @param netifs [Array<NetworkInterface>]
    # @param netif [NetworkInterface]
    def add_netif(netifs, netif)
      network_backend && network_backend.add_netif(netifs, netif)
    end

    # Called when a network interface is removed from a container
    # @param netifs [Array<NetworkInterface>]
    # @param netif [NetworkInterface]
    def remove_netif(netifs, netif)
      network_backend && network_backend.remove_netif(netifs, netif)
    end

    # Called when an existing network interface is renamed
    # @param netifs [Array<NetworkInterface>]
    # @param netif [NetworkInterface]
    # @param old_name [String]
    def rename_netif(netifs, netif, old_name)
      network_backend && network_backend.rename_netif(netifs, netif, old_name)
    end

    # Generate systemd/udev rules to configure network interface names
    # @param netifs [Array<NetworkInterface>]
    def generate_netif_rename_rules(netifs)
      ErbTemplate.render_to_if_changed(
        'network/systemd_link',
        { netifs: },
        File.join(rootfs, 'etc/systemd/network/10-vpsadmin-netifs.link')
      )

      ErbTemplate.render_to_if_changed(
        'network/udev_rules',
        { netifs: },
        File.join(rootfs, 'etc/udev/rules.d/10-vpsadmin-netifs.rules')
      )
    end

    # Configure DNS resolvers
    # @param resolvers [Array<String>]
    def dns_resolvers(resolvers)
      writable?(File.join(rootfs, 'etc', 'resolv.conf')) do |path|
        File.open("#{path}.new", 'w') do |f|
          resolvers.each { |v| f.puts("nameserver #{v}") }
          f.puts('options edns0')
        end

        File.rename("#{path}.new", path)
      end
    end

    # Add key to ~/.ssh/authorized_keys
    # @param public_key [String]
    def add_authorized_key(public_key)
      root_dir = File.join(rootfs, 'root')
      ssh_dir = File.join(root_dir, '.ssh')
      authorized_keys = File.join(ssh_dir, 'authorized_keys')

      FileUtils.mkdir_p(root_dir, mode: 0o700)
      FileUtils.mkdir_p(ssh_dir, mode: 0o700)

      unless File.exist?(authorized_keys)
        File.write(authorized_keys, "#{public_key}\n")
        File.chmod(0o600, authorized_keys)
        return
      end

      # Walk through the file, write the key if it is not there yet
      # For some reason, when File.open is given a block, it does not raise
      # exceptions like "Errno::EDQUOT: Disk quota exceeded", so don't use it.
      f = File.open(authorized_keys, 'r+')
      last_line = ''

      f.each_line do |line|
        last_line = line

        if line.strip == public_key
          f.close
          return # rubocop:disable Lint/NonLocalExitFromIterator
        end
      end

      # The key is not there yet
      f.write("\n") unless last_line.end_with?("\n")
      f.write(public_key)
      f.write("\n")
      f.close
    end

    # Remove key from ~/.ssh/authorized_keys
    def remove_authorized_key(public_key)
      authorized_keys = File.join(rootfs, 'root/.ssh/authorized_keys')

      return unless File.exist?(authorized_keys)

      tmp = File.join(File.dirname(authorized_keys), ".vpsadmin-#{File.basename(authorized_keys)}")

      src = File.open(authorized_keys, 'r')
      dst = File.open(tmp, 'w')

      src.each_line do |line|
        next if line.strip == public_key

        dst.write(line)
      end

      src.close
      dst.close

      File.rename(tmp, authorized_keys)
    end

    def install_user_script(content)
      raise NotImplementedError
    end

    def deploy_cloud_init(format, content)
      nocloud = File.join(rootfs, 'var/lib/cloud/seed/nocloud')

      FileUtils.mkdir_p(nocloud)

      File.open(File.join(nocloud, 'meta-data'), 'w') do |f|
        f.puts("instance-id: #{vps_config.vps_id}")
      end

      File.open(File.join(nocloud, 'network-config'), 'w') do |f|
        f.puts(<<~END)
          network:
            version: 2
            ethernets: {}
        END
      end

      user_data = File.join(nocloud, 'user-data')

      File.open(user_data, 'w') do |f|
        f.puts(content)
      end

      return unless format == 'cloudinit_script'

      File.chmod(0o755, user_data)
    end

    protected

    # @return [Network::Base, nil]
    attr_reader :network_backend

    # Return a class which is used for network configuration
    #
    # The class should be a subclass of {DistConfig::Network::Base}.
    #
    # If an array of classes is returned, they are instantiated and the first
    # class for which {DistConfig::Network::Base#usable?} returns true is used.
    # An exception is raised if no class is found to be usable.
    #
    # If `nil` is returned, you are expected to implement {#network} and other
    # methods for network configuration yourself.
    #
    # @return [Class, Array<Class>, nil]
    def network_class
      raise NotImplementedError
    end

    # @return [Network::Base, nil]
    def instantiate_network_class
      klass = network_class

      if klass.nil?
        log(:debug, 'Using distribution-specific network configuration')
        nil

      elsif klass.is_a?(Array)
        klass.each do |k|
          inst = k.new(self)

          if inst.usable?
            log(:debug, "Using #{k} for network configuration")
            return inst
          end
        end

        log(:warn, "No network class usable for #{self.class}")
        nil

      else
        log(:debug, "Using #{network_class} for network configuration")
        network_class.new(self)
      end
    end
  end
end
