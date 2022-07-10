class VpsBgpIpAddress < ActiveRecord::Base
  belongs_to :vps_bgp_peer
  belongs_to :ip_address

  enum priority: %i(no_priority low_priority normal_priority high_priority)

  validate :check_ip_address

  include Confirmable

  protected
  def check_ip_address
    if ip_address.network_interface
      errors.add(:ip_address, 'must not be routed to a network interface')
    end
  end
end
