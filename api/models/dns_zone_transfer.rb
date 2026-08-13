require_relative 'confirmable'

class DnsZoneTransfer < ApplicationRecord
  belongs_to :dns_zone
  belongs_to :host_ip_address
  belongs_to :dns_tsig_key
  has_many :dns_server_zone_transfer_logs, dependent: :nullify
  has_many :dns_server_zone_primary_transfer_states, dependent: :delete_all

  enum :peer_type, %i[primary_type secondary_type]

  validate :check_peer_type
  validate :check_ownership

  include Confirmable

  scope :existing, lambda {
    where(confirmed: [confirmed(:confirm_create), confirmed(:confirmed)])
  }

  def self.preload_direct_transfer_stats(transfers)
    transfers = transfers.to_a
    primary_transfers = transfers.select(&:primary_type?)
    zone_ids = primary_transfers.map(&:dns_zone_id).uniq
    transfer_ids = primary_transfers.map(&:id)

    if transfer_ids.empty?
      transfers.each do |transfer|
        transfer.instance_variable_set(:@direct_transfer_stats, empty_direct_transfer_stats_hash)
      end
      return transfers
    end

    server_counts =
      ::DnsServerZone
      .existing
      .secondary_type
      .joins(:dns_server)
      .where(dns_zone_id: zone_ids, dns_servers: { hidden: false })
      .group(:dns_zone_id)
      .count

    state_rows =
      ::DnsServerZonePrimaryTransferState
      .joins(dns_server_zone: :dns_server)
      .merge(::DnsServerZone.existing.secondary_type)
      .where(
        dns_zone_transfer_id: transfer_ids,
        dns_server_zones: { dns_zone_id: zone_ids },
        dns_servers: { hidden: false }
      )
      .group(:dns_zone_transfer_id)
      .pluck(
        :dns_zone_transfer_id,
        Arel.sql("SUM(status = #{::DnsServerZonePrimaryTransferState.statuses[:failed]})"),
        Arel.sql("SUM(status = #{::DnsServerZonePrimaryTransferState.statuses[:success]})"),
        Arel.sql('MAX(last_attempt_at)')
      )
      .to_h do |transfer_id, failed_count, success_count, last_attempt_at|
        [
          transfer_id,
          {
            failed_count: failed_count.to_i,
            success_count: success_count.to_i,
            last_attempt_at:
          }
        ]
      end

    transfers.each do |transfer|
      stats = state_rows.fetch(transfer.id, {}).merge(
        server_count: transfer.primary_type? ? server_counts.fetch(transfer.dns_zone_id, 0) : 0,
        failed_count: state_rows.dig(transfer.id, :failed_count).to_i,
        success_count: state_rows.dig(transfer.id, :success_count).to_i,
        last_attempt_at: state_rows.dig(transfer.id, :last_attempt_at)
      )
      transfer.instance_variable_set(:@direct_transfer_stats, stats)
    end

    transfers
  end

  def self.empty_direct_transfer_stats_hash
    {
      server_count: 0,
      failed_count: 0,
      success_count: 0,
      last_attempt_at: nil
    }
  end

  def ip_addr
    host_ip_address.ip_addr
  end

  def server_name
    host_ip_address.reverse_record_value
  end

  def server_opts
    {
      id:,
      kind: 'user_primary',
      ip_addr: host_ip_address.ip_addr,
      tsig_key: dns_tsig_key && {
        name: dns_tsig_key.name,
        algorithm: dns_tsig_key.algorithm,
        secret: dns_tsig_key.secret
      }
    }
  end

  def transfer_check_status
    stats = direct_transfer_stats

    if stats[:failed_count] > 0
      'failed'
    elsif stats[:server_count] > 0 && stats[:success_count] == stats[:server_count]
      'success'
    else
      'pending'
    end
  end

  def last_transfer_check_at
    direct_transfer_stats[:last_attempt_at]
  end

  def transfer_check_failed_count
    direct_transfer_stats[:failed_count]
  end

  def transfer_check_success_count
    direct_transfer_stats[:success_count]
  end

  def transfer_check_server_count
    direct_transfer_stats[:server_count]
  end

  def transfer_check_pending_count
    transfer_check_server_count - transfer_check_failed_count - transfer_check_success_count
  end

  protected

  def direct_transfer_stats
    return @direct_transfer_stats if defined?(@direct_transfer_stats)
    return empty_direct_transfer_stats unless primary_type?

    self.class.preload_direct_transfer_stats([self])
    @direct_transfer_stats
  end

  def empty_direct_transfer_stats
    self.class.empty_direct_transfer_stats_hash
  end

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
