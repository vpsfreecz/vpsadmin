class DnsZoneTransfer < ApplicationRecord
  belongs_to :dns_zone
  belongs_to :host_ip_address
  belongs_to :dns_tsig_key

  enum peer_type: %i[primary_type secondary_type]

  validate :check_peer_type
  validate :check_ownership

  def ip_addr
    host_ip_address.ip_addr
  end

  def server_name
    host_ip_address.reverse_record_value
  end

  def server_opts
    {
      ip_addr: host_ip_address.ip_addr,
      tsig_key: dns_tsig_key && {
        name: dns_tsig_key.name,
        algorithm: dns_tsig_key.algorithm,
        secret: dns_tsig_key.secret
      }
    }
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

    if dns_tsig_key && (dns_zone.user || dns_tsig_key.user) && dns_tsig_key.user != dns_zone.user
      errors.add(:dns_tsig_key, 'TSIG key and zone owner mismatch')
    end
    # rubocop:enable Style/GuardClause
  end
end
