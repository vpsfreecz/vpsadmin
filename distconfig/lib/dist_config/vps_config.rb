require 'json'

module DistConfig
  class VpsConfig
    # @return [Integer]
    attr_reader :vps_id

    # @return [String]
    attr_reader :rootfs_label

    # @return [String]
    attr_reader :rescue_label

    # @return [String]
    attr_reader :rescue_rootfs_mountpoint

    # @return [String]
    attr_accessor :distribution

    # @return [String]
    attr_accessor :version

    # @return [String]
    attr_accessor :arch

    # @return [String]
    attr_accessor :variant

    # @return [Hostname, nil]
    attr_accessor :hostname

    # @return [Integer]
    attr_reader :start_menu_timeout

    # @return [String]
    attr_reader :init_cmd

    # @return [Array<String>]
    attr_accessor :dns_resolvers

    # @return [Array<NetworkInterface>]
    attr_reader :network_interfaces

    def initialize(path)
      @path = path
      @cfg = JSON.parse(File.read(path))

      @vps_id = @cfg.fetch('vps_id')
      @rootfs_label = @cfg.fetch('rootfs_label')
      @rescue_label = @cfg.fetch('rescue_label', nil)
      @rescue_rootfs_mountpoint = @cfg.fetch('rescue_rootfs_mountpoint', nil)
      @distribution = @cfg.fetch('distribution')
      @version = @cfg.fetch('version')
      @arch = @cfg.fetch('arch')
      @variant = @cfg.fetch('variant')
      @start_menu_timeout = @cfg.fetch('start_menu_timeout')
      @init_cmd = @cfg.fetch('init_cmd')
      @hostname = @cfg['hostname'] && Hostname.new(@cfg['hostname'])
      @dns_resolvers = @cfg.fetch('dns_resolvers', [])
      @network_interfaces = @cfg.fetch('network_interfaces', []).map { |v| NetworkInterface.new(v) }
    end

    def dump
      {
        'vps_id' => @vps_id,
        'rootfs_label' => @rootfs_label,
        'rescue_label' => @rescue_label,
        'rescue_rootfs_mountpoint' => @rescue_rootfs_mountpoint,
        'distribution' => @distribution,
        'version' => @version,
        'arch' => @arch,
        'variant' => @variant,
        'start_menu_timeout' => @start_menu_timeout,
        'init_cmd' => @init_cmd,
        'hostname' => @hostname && @hostname.to_s,
        'dns_resolvers' => @dns_resolvers,
        'network_interfaces' => @network_interfaces.map(&:dump)
      }
    end

    def save
      tmp = "#{@path}.new"

      File.write(tmp, dump.to_json)
      File.rename(tmp, @path)
    end
  end
end
