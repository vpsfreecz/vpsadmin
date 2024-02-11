require 'libosctl'
require 'singleton'
require 'thread'

module NodeCtld
  # {VethMap} is a singleton class that stores real names of per-VPS veth
  # interfaces.
  class VethMap
    include Singleton

    include OsCtl::Lib::Utils::Log
    include Utils::System
    include Utils::OsCtl

    class << self
      # @param [Integer] vps_id
      # @return [Hash<String,String>] vps veth name => host veth name
      def [](vps_id)
        instance[vps_id]
      end

      # @param [Integer] vps_id
      # @param [String] ct_veth
      # @return [String, nil]
      def get(vps_id, ct_veth)
        instance.get(vps_id, ct_veth)
      end

      # Update VPS interface
      # @param [Integer] vps_id
      def set(vps_id, ct_veth, host_veth)
        instance.set(vps_id, ct_veth, host_veth)
      end

      # Reset all VPS interfaces
      # @param [Integer] vps_id
      def reset(vps_id)
        instance.reset(vps_id)
      end

      # Load all interfaces anew
      def update_all
        instance.update_all
      end

      # Dump map contents
      # @return [Hash]
      def dump
        instance.dump
      end

      # Iterate over mapped veth interfaces
      # @yieldparam vps_id [Integer]
      # @yieldparam vps_name veth name as seen in the VPS
      # @yieldparam host_name veth name as seen on the host
      def each_veth(&block)
        instance.each_veth(&block)
      end
    end

    def initialize
      @map = {}
      @mutex = Mutex.new
      @update_thread = Thread.new { run_update_all }
      sync { load_all }
    end

    def [](vps_id)
      k = vps_id.to_s

      sync do
        @map[k] = fetch(k) unless @map.has_key?(k)
        @map[k]
      end
    end

    def get(vps_id, ct_veth)
      k = vps_id.to_s

      sync do
        vps_veths = @map[k]
        next if vps_veths.nil?

        vps_veths[ct_veth]
      end
    end

    def set(vps_id, ct_veth, host_veth)
      k = vps_id.to_s

      sync do
        @map[k] = {} unless @map.has_key?(k)
        @map[k][ct_veth] = host_veth
      end
    end

    def reset(vps_id)
      k = vps_id.to_s

      sync do
        @map[k].clear if @map.has_key?(k)
      end
    end

    def update_all
      sync do
        netifs = list_all
        @map.clear

        netifs.each do |netif|
          next if netif[:veth].nil?

          @map[netif[:ctid]] ||= {}
          @map[netif[:ctid]][netif[:name]] = netif[:veth]
        end
      end
    end

    def dump
      sync do
        Hash[@map.map { |k, v| [k.dup, v.clone] }]
      end
    end

    def each_veth
      sync do
        @map.each do |vps_id, netmap|
          netmap.each do |vps, host|
            next unless host

            yield(vps_id, vps, host)
          end
        end
      end
    end

    def log_type
      'veth_map'
    end

    protected

    def fetch(vps_id)
      entry = {}

      osctl_parse(%i[ct netif ls], vps_id).each do |netif|
        entry[netif[:name]] = netif[:veth]
      end

      entry
    end

    def list_all
      osctl_parse(%i[ct netif ls])
    end

    def load_all
      list_all.each do |netif|
        next if netif[:veth].nil?

        @map[netif[:ctid]] ||= {}
        @map[netif[:ctid]][netif[:name]] = netif[:veth]
      end
    end

    def run_update_all
      loop do
        sleep($CFG.get(:vpsadmin, :veth_map_interval))
        update_all
      end
    end

    def sync(&block)
      @mutex.synchronize(&block)
    end
  end
end
