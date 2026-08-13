# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DnsZone do
  def create_primary!(zone:, ip:)
    network = ip.include?(':') ? SpecSeed.network_v6 : SpecSeed.network_v4
    ip_address = IpAddress.create!(
      network:,
      ip_addr: ip,
      prefix: network.split_prefix,
      size: 1,
      user: zone.user
    )
    host_ip = HostIpAddress.create!(ip_address:, ip_addr: ip, user_created: true)
    DnsZoneTransfer.create!(
      dns_zone: zone,
      host_ip_address: host_ip,
      peer_type: :primary_type,
      confirmed: DnsZoneTransfer.confirmed(:confirmed)
    )
  end

  it 'selects the transfer source address in the primary address family' do
    at = Time.current
    zone = create_dns_zone!(user: SpecSeed.user, source: :external_source, email: nil)
    dns_server = create_dns_server!(
      node: SpecSeed.node,
      ipv4_addr: '192.0.2.53',
      user_dns_zone_type: :secondary_type
    )
    dns_server.update!(ipv6_addr: '2001:db8::53')
    server_zone = create_dns_server_zone!(
      dns_zone: zone,
      dns_server:,
      zone_type: :secondary_type
    )
    ipv4_state = create_state!(
      server_zone:,
      transfer: create_primary!(zone:, ip: '192.0.2.214'),
      at:
    )
    ipv6_state = create_state!(
      server_zone:,
      transfer: create_primary!(zone:, ip: '2001:db8::214'),
      at:
    )

    expect(ipv4_state.secondary_source_addr).to eq('192.0.2.53')
    expect(ipv6_state.secondary_source_addr).to eq('2001:db8::53')

    dns_server.update!(ipv6_addr: nil)
    expect(ipv6_state.secondary_source_addr).to be_nil
  end

  def create_state!(server_zone:, transfer:, at:, eligible: false)
    DnsServerZonePrimaryTransferState.create!(
      dns_server_zone: server_zone,
      dns_zone_transfer: transfer,
      configuration_generation:
        server_zone.primary_transfer_configuration_generation,
      last_event_key: SecureRandom.hex(32),
      status: :failed,
      failure_class: :primary,
      last_attempt_kind: :ixfr_probe,
      failed_since: at - 31.minutes,
      last_failure_at: at,
      last_attempt_at: at,
      alert_eligible_at: eligible ? at - 1.minute : nil,
      reason_observed_at: at,
      reason_code: 'refused',
      reason: 'The primary refused the transfer'
    )
  end

  it 'opens on eligible paths and keeps an incident until all failures recover' do
    at = Time.utc(2026, 8, 13, 12, 0, 0)
    zone = create_dns_zone!(user: SpecSeed.user, source: :external_source, email: nil)
    primary = create_primary!(zone:, ip: '192.0.2.210')
    servers = 2.times.map do |i|
      create_dns_server_zone!(
        dns_zone: zone,
        dns_server: create_dns_server!(
          node: create_node!(name: "dns-monitor-#{i}-#{SecureRandom.hex(3)}"),
          user_dns_zone_type: :secondary_type
        ),
        zone_type: :secondary_type
      )
    end
    eligible = create_state!(server_zone: servers[0], transfer: primary, at:, eligible: true)
    young = create_state!(server_zone: servers[1], transfer: primary, at:, eligible: false)

    counted = described_class
              .with_alert_eligible_primary_transfer_state_counts(at:)
              .find(zone.id)
    expect(counted.alert_eligible_primary_transfer_state_count).to eq(1)
    expect(counted.failed_primary_transfer_state_count).to eq(2)
    expect(counted.primary_transfer_failure_monitor_passed?(incident_active: false)).to be(false)

    eligible.update!(
      status: :success,
      failure_class: nil,
      failed_since: nil,
      last_failure_at: nil,
      alert_eligible_at: nil,
      reason_code: nil,
      reason: nil
    )
    overlap = described_class
              .with_alert_eligible_primary_transfer_state_counts(at:)
              .find(zone.id)
    expect(overlap.primary_transfer_failure_monitor_passed?(incident_active: false)).to be(true)
    expect(overlap.primary_transfer_failure_monitor_passed?(incident_active: true)).to be(false)

    young.update!(
      status: :success,
      failure_class: nil,
      failed_since: nil,
      last_failure_at: nil,
      alert_eligible_at: nil,
      reason_code: nil,
      reason: nil
    )
    recovered = described_class
                .with_alert_eligible_primary_transfer_state_counts(at:)
                .find(zone.id)
    expect(recovered.primary_transfer_failure_monitor_passed?(incident_active: true)).to be(true)
  end

  it 'starts a new generation and drops state across enable changes' do
    at = Time.current
    zone = create_dns_zone!(user: SpecSeed.user, source: :external_source, email: nil)
    primary = create_primary!(zone:, ip: '192.0.2.211')
    server_zone = create_dns_server_zone!(
      dns_zone: zone,
      dns_server: create_dns_server!(
        node: SpecSeed.node,
        user_dns_zone_type: :secondary_type
      ),
      zone_type: :secondary_type
    )
    state = create_state!(server_zone:, transfer: primary, at:)
    original_generation = zone.primary_transfer_generation

    zone.update!(enabled: false)
    expect(zone.primary_transfer_tracking_started_at).to be_nil
    expect(zone.primary_transfer_generation).to be_nil
    expect(DnsServerZonePrimaryTransferState.exists?(state.id)).to be(false)

    zone.update!(enabled: true)
    expect(zone.primary_transfer_tracking_started_at).not_to be_nil
    expect(zone.primary_transfer_generation).not_to eq(original_generation)
  end

  it 'starts a new generation across source changes' do
    zone = create_dns_zone!(user: SpecSeed.user, source: :external_source, email: nil)
    original_generation = zone.primary_transfer_generation

    zone.update!(zone_source: :internal_source, email: 'dns@example.test')
    expect(zone.primary_transfer_generation).to be_nil

    zone.update!(zone_source: :external_source, email: nil)
    expect(zone.primary_transfer_generation).not_to eq(original_generation)
  end

  it 'preserves unchanged failed paths when primary configuration rotates' do
    at = Time.current
    zone = create_dns_zone!(user: SpecSeed.user, source: :external_source, email: nil)
    primary = create_primary!(zone:, ip: '192.0.2.213')
    server_zone = create_dns_server_zone!(
      dns_zone: zone,
      dns_server: create_dns_server!(
        node: SpecSeed.node,
        user_dns_zone_type: :secondary_type
      ),
      zone_type: :secondary_type
    )
    state = create_state!(server_zone:, transfer: primary, at:, eligible: true)
    original_generation = zone.primary_transfer_generation

    zone.rotate_primary_transfer_generation!

    expect(zone.primary_transfer_generation).not_to eq(original_generation)
    expect(state.reload).to be_failed
    monitored_zone = described_class
                     .with_alert_eligible_primary_transfer_state_counts(at:)
                     .find(zone.id)
    expect(monitored_zone.primary_transfer_failure_monitor_passed?(incident_active: true)).to be(false)
  end

  it 'retains path state while pruning its old latest log reference' do
    at = 366.days.ago
    zone = create_dns_zone!(user: SpecSeed.user, source: :external_source, email: nil)
    primary = create_primary!(zone:, ip: '192.0.2.212')
    server_zone = create_dns_server_zone!(
      dns_zone: zone,
      dns_server: create_dns_server!(
        node: SpecSeed.node,
        user_dns_zone_type: :secondary_type
      ),
      zone_type: :secondary_type
    )
    log = DnsServerZoneTransferLog.create!(
      dns_server_zone: server_zone,
      dns_zone_transfer: primary,
      event_key: SecureRandom.hex(32),
      event_at: at,
      status: :failed,
      attempt_kind: :ixfr_probe,
      failure_class: :primary
    )
    state = create_state!(server_zone:, transfer: primary, at:, eligible: true)
    state.update!(last_transfer_log: log)

    expect { DnsServerZoneTransferLog.prune! }.not_to change(
      DnsServerZonePrimaryTransferState,
      :count
    )
    expect(state.reload.last_transfer_log).to be_nil
  end
end
