class HostIpAddress < ActiveRecord::Base
  belongs_to :ip_address
  has_many :routed_via_addresses,
           class_name: 'IpAddress', foreign_key: :route_via_id

  def assigned?
    !order.nil?
  end

  alias assigned assigned?

  def version
    ip_address.network.ip_version
  end

  # @return [::User, nil]
  def current_owner
    ip_address.current_owner
  end
end
