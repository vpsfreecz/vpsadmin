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
      @cfg = JSON.parse(File.read(path))

      @distribution = @cfg.fetch('distribution')
      @version = @cfg.fetch('version')
      @hostname = @cfg['hostname'] && Hostname.new(@cfg['hostname'])
      @dns_resolvers = @cfg.fetch('dns_resolvers', nil)
      @network_interfaces = @cfg.fetch('network_interfaces', []).map { |v| NetworkInterface.new(v) }
    end
  end
end
