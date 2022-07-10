class VpsBgpPeer < ActiveRecord::Base
  belongs_to :vps
  belongs_to :host_ip_address
  has_many :vps_bgp_ip_addresses, dependent: :delete_all
  has_one :vps_bgp_asn, through: :vps

  enum :protocol, %i[ipv4 ipv6 ipv46]

  validates :host_ip_address, presence: true
  validate :check_address

  include Confirmable
  include Lockable

  def node_asn
    vps_bgp_asn.node_asn
  end

  def vps_asn
    vps_bgp_asn.vps_asn
  end

  protected

  def check_address
    return if vps.user_id == host_ip_address.ip_address.user_id

    errors.add(:vps, 'mismatching host IP address')
    errors.add(:host_ip_address, 'mismatching VPS')
  end
end
