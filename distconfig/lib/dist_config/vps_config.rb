require 'json'

module DistConfig
  class VpsConfig
    # @return [String]
    attr_reader :distribution

    # @return [String]
    attr_reader :version

    # @return [String, nil]
    attr_reader :hostname

    # @return [Array<String>, nil]
    attr_reader :dns_resolvers

    # @return [Array<NetworkInterface>]
    attr_reader :network_interfaces

    def initialize(path)
      @path = path
      @cfg = JSON.parse(File.read(path))

      @distribution = @cfg.fetch('distribution')
      @version = @cfg.fetch('version')
      @hostname = @cfg['hostname'] && Hostname.new(@cfg['hostname'])
      @dns_resolvers = @cfg.fetch('dns_resolvers', nil)
      @network_interfaces = @cfg.fetch('network_interfaces', []).map { |v| NetworkInterface.new(v) }
    end

    def dump
      {
        'distribution' => @distribution,
        'version' => @version,
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
