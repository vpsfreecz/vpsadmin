class DnsServer < ApplicationRecord
  belongs_to :node
  has_many :dns_server_zones
  has_many :dns_zones, through: :dns_server_zones

  enum :user_dns_zone_type, %i[primary_type secondary_type]

  validates :name, presence: true
  validate :check_name
  validate :check_ip_addresses

  def check_name
    return unless name.end_with?('.')

    errors.add(:name, 'must not have a trailing dot')
  end

  def check_ip_addresses
    return if ipv4_addr || ipv6_addr

    errors.add(:ipv4_addr, 'provide at least one address')
    errors.add(:ipv6_addr, 'provide at least one address')
  end
end
