require 'json'

module DistConfig
  class VpsConfig
    # @return [String]
    attr_reader :rootfs_label

    # @return [String]
    attr_reader :rescue_label

    # @return [String]
    attr_reader :rescue_rootfs_mountpoint

    # @return [String]
    attr_reader :distribution

    # @return [String]
    attr_reader :version

    # @return [String]
    attr_reader :arch

    # @return [String]
    attr_reader :variant

    # @return [Hostname, nil]
    attr_accessor :hostname

    # @return [Array<String>]
    attr_accessor :dns_resolvers

    # @return [Array<NetworkInterface>]
    attr_reader :network_interfaces

    def initialize(path)
      @path = path
      @cfg = JSON.parse(File.read(path))

      @rootfs_label = @cfg.fetch('rootfs_label')
      @rescue_label = @cfg.fetch('rescue_label', nil)
      @rescue_rootfs_mountpoint = @cfg.fetch('rescue_rootfs_mountpoint', nil)
      @distribution = @cfg.fetch('distribution')
      @version = @cfg.fetch('version')
      @arch = @cfg.fetch('arch')
      @variant = @cfg.fetch('variant')
      @hostname = @cfg['hostname'] && Hostname.new(@cfg['hostname'])
      @dns_resolvers = @cfg.fetch('dns_resolvers', [])
      @network_interfaces = @cfg.fetch('network_interfaces', []).map { |v| NetworkInterface.new(v) }
    end

    def dump
      {
        'rootfs_label' => @rootfs_label,
        'rescue_label' => @rescue_label,
        'rescue_rootfs_mountpoint' => @rescue_rootfs_mountpoint,
        'distribution' => @distribution,
        'version' => @version,
        'arch' => @arch,
        'variant' => @variant,
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
