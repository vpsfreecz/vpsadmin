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
end
