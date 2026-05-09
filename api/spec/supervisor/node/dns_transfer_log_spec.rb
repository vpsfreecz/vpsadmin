# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::Supervisor::Node::DnsTransferLog do
  def create_zone!(name:, user:, source: :external_source)
    DnsZone.create!(
      name: name,
      user: user,
      zone_role: :forward_role,
      zone_source: source,
      dnssec_enabled: false,
      enabled: true,
      label: '',
      default_ttl: 3600,
      email: nil
    )
  end

  def create_server!(node:)
    DnsServer.create!(
      node: node,
      name: "ns-transfer-#{SecureRandom.hex(4)}",
      ipv4_addr: '192.0.2.10',
      hidden: false,
      enable_user_dns_zones: true,
      user_dns_zone_type: :secondary_type
    )
  end

  def create_server_zone!(node: SpecSeed.node)
    zone = create_zone!(
      name: "transfer-log-#{SecureRandom.hex(4)}.example.test.",
      user: SpecSeed.user
    )
    server = create_server!(node:)

    DnsServerZone.create!(
      dns_server: server,
      dns_zone: zone,
      zone_type: :secondary_type,
      confirmed: DnsServerZone.confirmed(:confirmed)
    )
  end

  def transfer_event(server_zone, attrs = {})
    {
      'name' => server_zone.dns_zone.name,
      'time' => Time.utc(2026, 5, 9, 12, 0, 0).to_i,
      'status' => 'failed',
      'reason_code' => 'refused',
      'reason' => 'The primary DNS server refused the transfer',
      'primary_addr' => '192.0.2.1',
      'serial' => nil,
      'message' => 'REFUSED',
      'raw_message' => 'Transfer status: REFUSED',
      'source_cursor' => 'cursor-1',
      'event_key' => SecureRandom.hex(32)
    }.merge(attrs)
  end

  it 'stores transfer logs and updates the latest transfer state' do
    server_zone = create_server_zone!
    supervisor = described_class.new(nil, SpecSeed.node)
    event = transfer_event(server_zone)

    expect do
      supervisor.send(:save_event, event)
    end.to change(DnsServerZoneTransferLog, :count).by(1)

    log = DnsServerZoneTransferLog.last
    expect(log).to have_attributes(
      dns_server_zone: server_zone,
      status: 'failed',
      reason_code: 'refused',
      primary_addr: '192.0.2.1'
    )

    server_zone.reload
    expect(server_zone.last_transfer_log).to eq(log)
    expect(server_zone.last_transfer_status).to eq('failed')
    expect(server_zone.last_transfer_reason_code).to eq('refused')
    expect(server_zone.last_transfer_reason).to eq('The primary DNS server refused the transfer')
  end

  it 'ignores duplicate events by event key' do
    server_zone = create_server_zone!
    supervisor = described_class.new(nil, SpecSeed.node)
    event = transfer_event(server_zone, 'event_key' => 'duplicate-key')

    supervisor.send(:save_event, event)
    supervisor.send(:save_event, event)

    expect(DnsServerZoneTransferLog.where(event_key: 'duplicate-key').count).to eq(1)
  end

  it 'does not let a started event clear an existing failure' do
    server_zone = create_server_zone!
    supervisor = described_class.new(nil, SpecSeed.node)
    supervisor.send(:save_event, transfer_event(server_zone))

    supervisor.send(
      :save_event,
      transfer_event(
        server_zone,
        'status' => 'started',
        'reason_code' => nil,
        'reason' => nil,
        'message' => 'Transfer started',
        'event_key' => SecureRandom.hex(32),
        'time' => Time.utc(2026, 5, 9, 12, 5, 0).to_i
      )
    )

    expect(server_zone.reload.last_transfer_status).to eq('failed')
    expect(server_zone.last_transfer_reason_code).to eq('refused')
  end

  it 'clears failure reason after a later successful transfer' do
    server_zone = create_server_zone!
    supervisor = described_class.new(nil, SpecSeed.node)
    supervisor.send(:save_event, transfer_event(server_zone))

    supervisor.send(
      :save_event,
      transfer_event(
        server_zone,
        'status' => 'success',
        'reason_code' => nil,
        'reason' => nil,
        'serial' => 2_026_050_901,
        'message' => 'Transfer completed successfully',
        'event_key' => SecureRandom.hex(32),
        'time' => Time.utc(2026, 5, 9, 12, 10, 0).to_i
      )
    )

    server_zone.reload
    expect(server_zone.last_transfer_status).to eq('success')
    expect(server_zone.last_transfer_reason_code).to be_nil
    expect(server_zone.last_transfer_reason).to be_nil
    expect(server_zone.last_transfer_serial).to eq(2_026_050_901)
  end
end
