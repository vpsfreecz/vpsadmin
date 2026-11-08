# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::DnsZone::Update do
  around do |example|
    with_current_context(user: user) { example.run }
  end

  let(:user) { SpecSeed.user }

  def create_zone_with_server_zones
    zone = create_dns_zone!(
      user: user,
      source: :internal_source,
      name: "update-#{SecureRandom.hex(4)}.example.test."
    )

    2.times do
      create_dns_server_zone!(
        dns_zone: zone,
        dns_server: create_dns_server!(
          node: create_node!(name: "dns-update-#{SecureRandom.hex(3)}"),
          name: "ns-update-#{SecureRandom.hex(3)}"
        ),
        zone_type: :primary_type
      )
    end

    zone
  end

  it 'updates every server zone and reloads after runtime DNS changes' do
    zone = create_zone_with_server_zones

    chain, updated = described_class.fire(
      zone,
      default_ttl: 7200,
      email: 'hostmaster@example.test',
      dnssec_enabled: true,
      enabled: false
    )

    expect(updated.reload.default_ttl).to eq(7200)
    expect(tx_classes(chain)).to eq(
      [
        Transactions::DnsServerZone::Update,
        Transactions::DnsServer::Reload,
        Transactions::DnsServerZone::Update,
        Transactions::DnsServer::Reload,
        Transactions::Utils::NoOp
      ]
    )
    expect(tx_payload(chain, Transactions::DnsServerZone::Update)).to include(
      'new' => include(
        'default_ttl' => 7200,
        'email' => 'hostmaster@example.test',
        'dnssec_enabled' => true,
        'enabled' => false
      ),
      'original' => include(
        'default_ttl' => 3600,
        'email' => 'dns@example.test',
        'dnssec_enabled' => false,
        'enabled' => true
      )
    )
  end

  it 'rejects unsupported attributes' do
    zone = create_zone_with_server_zones

    expect do
      described_class.fire(zone, name: 'unsupported.example.test.')
    end.to raise_error(ArgumentError, /Cannot change DnsZone attribute/)
  end

  it 'saves no-op database-only updates without creating a chain' do
    zone = create_zone_with_server_zones

    chain, updated = described_class.fire(zone, label: 'new label')

    expect(chain).to be_nil
    expect(updated.reload.label).to eq('new label')
  end

  it 'confirms original values for changed runtime attrs and database-only attrs' do
    zone = create_zone_with_server_zones
    zone.update!(label: 'old label', original_enabled: true)

    chain, = described_class.fire(
      zone,
      label: 'new label',
      original_enabled: false,
      default_ttl: 7200
    )

    confirmation = confirmations_for(chain).find { |row| row.class_name == 'DnsZone' }

    expect(confirmation.attr_changes).to eq(
      'label' => 'old label',
      'original_enabled' => 1,
      'default_ttl' => 3600
    )
  end

  def external_zone_with_primary(enabled:)
    zone = create_dns_zone!(user:, source: :external_source, enabled:)
    server_zone = create_dns_server_zone!(
      dns_zone: zone,
      dns_server: create_dns_server!(node: SpecSeed.node),
      zone_type: :secondary_type
    )
    ip = create_ipv4_address_in_network!(
      network: create_private_network!(location: SpecSeed.location, purpose: :vps),
      location: SpecSeed.location,
      user:
    )
    transfer = create_dns_zone_transfer!(
      dns_zone: zone,
      host_ip_address: ip.host_ip_addresses.take!,
      peer_type: :primary_type
    )
    [zone, server_zone, transfer]
  end

  it 'keeps repeated validation stable and sends the persisted enable generation to the node' do
    zone, server_zone, transfer = external_zone_with_primary(enabled: true)
    replaced_generation = zone.primary_transfer_generation
    zone.update!(enabled: false)
    zone.enabled = true
    expect(zone).to be_valid
    prepared = zone.primary_transfer_generation
    started_at = zone.primary_transfer_tracking_started_at
    expect(zone).to be_valid
    expect(zone.primary_transfer_generation).to eq(prepared)

    chain, = described_class.fire(zone, enabled: true)
    payload = tx_payload(chain, Transactions::DnsServerZone::Update)

    expect(zone.reload.primary_transfer_generation).to eq(prepared)
    expect(payload.fetch('new')).to include(
      'primary_transfer_generation' => prepared,
      'primary_transfer_tracking_started_at' => started_at.to_i
    )
    expect(payload.fetch('original')).to include(
      'primary_transfer_generation' => nil,
      'primary_transfer_tracking_started_at' => nil
    )

    event = {
      'name' => zone.name,
      'dns_server_zone_id' => server_zone.id,
      'dns_zone_transfer_id' => transfer.id,
      'configuration_generation' => prepared,
      'time' => Time.current.to_i + 1,
      'status' => 'success',
      'attempt_kind' => 'ixfr_probe',
      'primary_addr' => transfer.ip_addr,
      'primary_serial' => 100,
      'secondary_serial' => 100,
      'message' => 'Transfer readiness confirmed',
      'event_key' => SecureRandom.hex(32)
    }
    supervisor = VpsAdmin::Supervisor::Node::DnsTransferLog.new(nil, SpecSeed.node)
    supervisor.send(:save_event, event.merge('configuration_generation' => replaced_generation))
    expect(server_zone.dns_server_zone_primary_transfer_states).to be_empty
    supervisor.send(:save_event, event)
    expect(server_zone.dns_server_zone_primary_transfer_states.take!.status).to eq('success')
  end

  [true, false].each do |enabled|
    it "restores database and node tracking together when #{enabled ? 'disabling' : 'enabling'} rolls back" do
      zone, server_zone, transfer = external_zone_with_primary(enabled:)
      old_generation = zone.primary_transfer_generation
      old_started_at = zone.primary_transfer_tracking_started_at
      if enabled
        DnsServerZonePrimaryTransferState.create!(
          dns_server_zone: server_zone,
          dns_zone_transfer: transfer,
          configuration_generation: old_generation,
          last_event_key: SecureRandom.hex(32),
          status: :failed,
          failure_class: :primary,
          failed_since: Time.current - 1.minute,
          last_failure_at: Time.current,
          last_attempt_kind: :ixfr_probe,
          last_attempt_at: Time.current
        )
      end

      chain, = described_class.fire(zone, enabled: !enabled)
      payload = tx_payload(chain, Transactions::DnsServerZone::Update)
      confirmation = confirmations_for(chain).find { |row| row.class_name == 'DnsZone' }

      expect(payload.fetch('new')).to include(
        'primary_transfer_generation' => zone.reload.primary_transfer_generation,
        'primary_transfer_tracking_started_at' => zone.primary_transfer_tracking_started_at&.to_i
      )
      # The node confirmation runner restores edit_before with raw SQL, without
      # ActiveRecord callbacks. Apply the actual chain's stored attributes.
      DnsZone.where(confirmation.row_pks).update_all(confirmation.attr_changes)
      expect(zone.reload.enabled).to eq(enabled)
      expect(zone.primary_transfer_generation).to eq(old_generation)
      expect(zone.primary_transfer_tracking_started_at&.to_i).to eq(old_started_at&.to_i)
      expect(payload.fetch('original')).to include(
        'primary_transfer_generation' => zone.primary_transfer_generation,
        'primary_transfer_tracking_started_at' => zone.primary_transfer_tracking_started_at&.to_i
      )
      expect(server_zone.dns_server_zone_primary_transfer_states).to be_empty
      expect(zone.primary_transfer_failure_resolution).not_to eq('recovered')

      # A later real transition must prepare a different token, not reuse the
      # rolled-back generation or manufacture a positive readiness observation.
      zone.update!(enabled: false) if enabled
      zone.update!(enabled: true)
      expect(zone.primary_transfer_generation).not_to eq(old_generation)
    end
  end
end
