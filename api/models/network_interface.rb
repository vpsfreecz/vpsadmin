require_relative 'lockable'

class NetworkInterface < ActiveRecord::Base
  belongs_to :vps
  has_many :ip_addresses
  has_many :host_ip_addresses, through: :ip_addresses
  enum kind: %i(venet veth_bridge veth_routed)

  NAME_RX = /\A[a-zA-Z\-_\.0-9]{1,30}\z/

  validates :name, presence: true, format: {
    with: NAME_RX,
    message: 'bad format'
  }

  include Lockable

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
  def add_route(ip, safe: false, host_addrs: [], via: nil)
    ::IpAddress.transaction do
      ip = ::IpAddress.find(ip.id) unless safe

      if ip.network.location_id != vps.node.location_id
        raise VpsAdmin::API::Exceptions::IpAddressInvalidLocation
      end

      if !ip.free? || (ip.user_id && ip.user_id != vps.user_id)
        raise VpsAdmin::API::Exceptions::IpAddressInUse
      end

      if !ip.user_id && ::IpAddress.joins(:network).where(
          user: vps.user,
          network_interface: nil,
          networks: {
            location_id: vps.node.location_id,
            ip_version: ip.network.ip_version,
            role: ::Network.roles[ip.network.role],
          }
      ).exists?
        raise VpsAdmin::API::Exceptions::IpAddressNotOwned
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

      TransactionChains::NetworkInterface::AddRoute.fire(
        self,
        [ip],
        host_addrs: host_addrs,
        via: via,
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

  # @param addr [HostIpAddress]
  def remove_host_address(addr)
    TransactionChains::NetworkInterface::DelHostIp.fire(self, [addr])
  end
end
