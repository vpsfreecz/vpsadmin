require 'forwardable'
require 'dist_config/helpers/common'

module DistConfig
  class Network::Base
    extend Forwardable

    include DistConfig::Helpers::Common
    include DistConfig::Helpers::File

    # @param configurator [DistConfig::Configurator]
    def initialize(configurator)
      @configurator = configurator
    end

    # Return true if this class can be used to configure the network
    # @return [Boolean]
    def usable?
      false
    end

    # @param netifs [Array<NetworkInterface>]
    def configure(netifs)
      configurator.generate_netif_rename_rules(netifs)
    end

    # Called when a new network interface is added to a container
    # @param netifs [Array<NetworkInterface>]
    # @param netif [NetworkInterface]
    def add_netif(netifs, netif); end

    # Called when a network interface is removed from a container
    # @param netifs [Array<NetworkInterface>]
    # @param netif [NetworkInterface]
    def remove_netif(netifs, netif); end

    # Called when an existing network interface is renamed
    # @param netifs [Array<NetworkInterface>]
    # @param netif [NetworkInterface]
    # @param old_name [String]
    def rename_netif(netifs, netif, old_name); end

    protected

    attr_reader :configurator

    def_delegators :configurator, :rootfs, :distribution, :version
  end
end
