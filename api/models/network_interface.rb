require_relative 'lockable'

class NetworkInterface < ActiveRecord::Base
  belongs_to :vps
  belongs_to :export
  has_many :ip_addresses
  has_many :host_ip_addresses, through: :ip_addresses
  enum kind: %i(venet veth_bridge veth_routed)

  NAME_RX = /\A[a-zA-Z\-_\.0-9]{1,30}\z/

  validates :name, presence: true, format: {
    with: NAME_RX,
    message: 'bad format'
  }

  include Lockable
  include HaveAPI::Hookable

  has_hook :create,
      desc: 'Called when a new NetworkInterface is being created, before the transaction to create it',
      context: 'TransactionChain instance',
      args: {
        network_interface: 'NetworkInterface instance'
      }

  has_hook :clone,
      desc: 'Called when a NetworkInterface is being cloned, after the transaction that creates it',
      context: 'TransactionChain instance',
      args: {
        src_network_interface: 'source NetworkInterface instance',
        dst_network_interface: 'target NetworkInterface instance',
      }

  has_hook :morph,
      desc: 'Called when a NetworkInterface is being morphed into a different type, after the transaction that morphs it',
      context: 'TransactionChain instance',
      args: {
        network_interface: 'NetworkInterface instance',
        original_kind: String,
        target_kind: String,
      }

  # @param new_name [String]
  def rename(new_name)
    fail 'invalid name' if NAME_RX !~ new_name
    TransactionChains::NetworkInterface::Rename.fire(self, new_name)
  end

  # Route `ip` to this interface
  #
  # Unless `safe` is true, the IP address `ip` is fetched from the database
  # again in a transaction to ensure that it has not been given
  # to any other VPS. Set `safe` to `true` if `ip` was fetched in a transaction.
  #
  # @param ip [IpAddress]
  # @param safe [Boolean]
  # @param host_addrs [Array<::HostIpAddress>] host addresses to assign
  # @param via [HostIpAddress, nil] route via on-interface address
  def add_route(ip, safe: false, host_addrs: [], via: nil, is_user: true)
    ::IpAddress.transaction do
      ip = ::IpAddress.find(ip.id) unless safe

      locnet = ip.network.location_networks.where(
        location_id: vps.node.location_id,
      ).take

      if locnet.nil?
        raise VpsAdmin::API::Exceptions::IpAddressInvalidLocation
      end

      if !ip.free? || (ip.user_id && ip.user_id != vps.user_id)
        raise VpsAdmin::API::Exceptions::IpAddressInUse
      end

      unless %w(any vps).include?(ip.network.purpose)
        raise VpsAdmin::API::Exceptions::IpAddressInvalid,
              "#{ip} cannot be assigned to a VPS"
      end

      if is_user && !ip.user_id && !locnet.userpick
        raise VpsAdmin::API::Exceptions::IpAddressInvalid,
              "#{ip} cannot be freely assigned to a VPS"
      end

      if via
        if !via.assigned?
          raise VpsAdmin::API::Exceptions::IpAddressNotAssigned,
                "#{via.ip_addr} is not assigned to any interface"

        elsif via.ip_address.network_interface_id != id
          raise VpsAdmin::API::Exceptions::IpAddressNotOwned,
                "#{via.ip_addr} does not belong to target network interface"

        elsif via.ip_address.network.ip_version != ip.network.ip_version
          raise ArgumentError, 'via uses incompatible IP version'
        end
      end

      TransactionChains::NetworkInterface::AddRoute.fire2(
        args: [self, [ip]],
        kwargs: {
          host_addrs: host_addrs,
          via: via,
        },
      )
    end
  end

  # Remove route of `ip` from this interface
  #
  # Unless `safe` is true, the IP address `ip` is fetched from the database
  # again in a transaction to ensure that it has not been given
  # to any other VPS. Set `safe` to `true` if `ip` was fetched in a transaction.
  #
  # @param ip [IpAddress]
  # @param safe [Boolean]
  def remove_route(ip, safe: false)
    ::IpAddress.transaction do
      ip = ::IpAddress.find(ip.id) unless safe

      if ip.network_interface_id != self.id
        raise VpsAdmin::API::Exceptions::IpAddressNotAssigned
      end

      routed_addrs = ::IpAddress.where(route_via: ip.host_ip_addresses)

      if routed_addrs.any?
        raise VpsAdmin::API::Exceptions::IpAddressInUse,
          "The following addresses are routed via host addresses from #{ip}:\n"+
          (routed_addrs.map { |v| "#{v} via #{v.route_via.ip_addr}" }.join(", \n"))
      end

      TransactionChains::NetworkInterface::DelRoute.fire(self, [ip])
    end
  end

  # @param addr [HostIpAddress]
  def add_host_address(addr)
    TransactionChains::NetworkInterface::AddHostIp.fire(self, [addr])
  end

  # Remove host address `addr` from this interface
  #
  # Unless `safe` is true, the IP address `addr` is fetched from the database
  # again in a transaction to ensure that it is still assigned to the interface.
  #
  # @param addr [HostIpAddress]
  # @param safe [Boolean]
  def remove_host_address(addr, safe: false)
    ::IpAddress.transaction do
      addr = ::HostIpAddress.find(addr.id) unless safe

      unless addr.assigned?
        raise VpsAdmin::API::Exceptions::IpAddressNotAssigned
      end

      TransactionChains::NetworkInterface::DelHostIp.fire(self, [addr])
    end
  end
end
