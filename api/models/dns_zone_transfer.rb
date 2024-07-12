class DnsZoneTransfer < ApplicationRecord
  belongs_to :dns_zone
  belongs_to :host_ip_address

  enum peer_type: %i[primary_type secondary_type]

  validate :check_peer_type
  validate :check_ownership

  def ip_addr
    host_ip_address.ip_addr
  end

  def server_name
    host_ip_address.reverse_record_value
  end

  protected

  def check_peer_type
    if dns_zone.internal_source? && primary_type?
      errors.add(:peer_type, 'internal zone can only have secondary_type transfers')
    elsif dns_zone.external_source? && secondary_type?
      errors.add(:peer_type, 'external zone can only have primary_type transfers')
    end
  end

  def check_ownership
    # rubocop:disable Style/GuardClause
    if dns_zone.user && dns_zone.user != host_ip_address.current_owner
      errors.add(:host_ip_address, 'target address does not belong to your account')
    end
    # rubocop:enable Style/GuardClause
  end
end
