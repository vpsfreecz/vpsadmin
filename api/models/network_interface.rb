class NetworkInterface < ActiveRecord::Base
  belongs_to :vps
  has_many :ip_addresses
  has_many :host_ip_addresses, through: :ip_addresses
  enum kind: %i(venet veth_bridge veth_routed)

  include Lockable

  # Route `ip` to this interface
  #
  # Unless `safe` is true, the IP address `ip` is fetched from the database
  # again in a transaction to ensure that it has not been given
  # to any other VPS. Set `safe` to `true` if `ip` was fetched in a transaction.
  #
  # @param ip [IpAddress]
  # @param safe [Boolean]
  def add_route(ip, safe: false)
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

      TransactionChains::NetworkInterface::AddRoute.fire(self, [ip])
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
