require 'filelock'
require 'fileutils'
require 'libosctl'

module NodeCtld
  class VpsConfig::TopLevel
    # @return [Integer]
    attr_reader :vps_id

    # @return [String]
    attr_accessor :uuid

    # @return [String]
    attr_accessor :vm_type

    # @return [String]
    attr_accessor :os

    # @return [String]
    attr_accessor :os_family

    # @return [Integer]
    attr_accessor :console_port

    # @return [String]
    attr_accessor :distribution

    # @return [String]
    attr_accessor :version

    # @return [OsCtl::Lib::Hostname]
    attr_accessor :hostname

    # @return [Array<String>]
    attr_accessor :dns_resolvers

    # @return [String]
    attr_accessor :rootfs_label

    # @return [String]
    attr_accessor :rescue_label

    # @return [String]
    attr_accessor :rescue_rootfs_mountpoint

    # @return [String]
    attr_accessor :init_cmd

    # @return [Integer]
    attr_accessor :start_menu_timeout

    # @return [VpsConfig::NetworkInterfaceList]
    attr_reader :network_interfaces

    # @param vps_id [Integer]
    # @param load [Boolean]
    def initialize(vps_id, load: true)
      @vps_id = vps_id

      if load && exist?
        self.load
      else
        @rootfs_label = 'vpsadmin-rootfs'
        @init_cmd = '/sbin/init'
        @start_menu_timeout = 5
        @network_interfaces = VpsConfig::NetworkInterfaceList.new
      end
    end

    def load
      data = lock do
        YAML.safe_load_file(path) || {}
      rescue ArgumentError, SystemCallError
        {}
      end

      @uuid = data.fetch('uuid', nil)
      @vm_type = data.fetch('vm_type', 'qemu_container')
      @os = data.fetch('os', 'linux')
      @os_family = data.fetch('os', 'other')
      @console_port = data.fetch('console_port', nil)
      @distribution = data.fetch('distribution', nil)
      @version = data.fetch('version', nil)
      @hostname = data['hostname'] && OsCtl::Lib::Hostname.new(data['hostname'])
      @dns_resolvers = data.fetch('dns_resolvers', [])
      @rootfs_label = data.fetch('rootfs_label', 'vpsadmin-rootfs')
      @rescue_label = data.fetch('rescue_label', nil)
      @rescue_rootfs_mountpoint = data.fetch('rescue_rootfs_mountpoint', nil)
      @init_cmd = data.fetch('init_cmd', '/sbin/init')
      @start_menu_timeout = data.fetch('start_menu_timeout', 5)
      @network_interfaces = VpsConfig::NetworkInterfaceList.load(data['network_interfaces'] || [])
    end

    def reset
      @network_interfaces.clear
      nil
    end

    def save
      save_to(path)
      true
    end

    def backup
      save_to(backup_path)
    end

    def restore
      lock do
        File.rename(backup_path, path)
        load
      end
    end

    def destroy(backup: true)
      self.backup if backup
      File.rename(path, destroyed_path)
    end

    def exist?
      File.exist?(path)
    end

    def backup_exist?
      File.exist?(backup_path)
    end

    def lock
      if @locked
        yield
      else
        FileUtils.mkpath(File.dirname(path))

        Filelock(path) do
          @locked = true
          ret = yield
          @locked = false
          ret
        end
      end
    end

    def to_distconfig
      config
    end

    protected

    def config
      {
        'vps_id' => vps_id,
        'vm_type' => vm_type,
        'os' => os,
        'os_family' => os_family,
        'console_port' => console_port,
        'hostname' => hostname && hostname.to_s,
        'distribution' => distribution,
        'version' => version,
        'dns_resolvers' => dns_resolvers,
        'rootfs_label' => rootfs_label,
        'rescue_label' => rescue_label,
        'rescue_rootfs_mountpoint' => rescue_rootfs_mountpoint,
        'init_cmd' => init_cmd,
        'start_menu_timeout' => start_menu_timeout,
        'network_interfaces' => network_interfaces.save
      }
    end

    def save_to(file)
      FileUtils.mkpath(File.dirname(file))
      lock do
        new_file = "#{file}.new"
        File.write(new_file, YAML.dump(config))
        File.rename(new_file, file)
      end
    end

    def path
      File.join($CFG.get(:vpsadmin, :vps_config_dir), "#{vps_id}.yml")
    end

    def backup_path
      "#{path}.backup"
    end

    def destroyed_path
      "#{path}.destroyed"
    end
  end
end
