# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::DnsZone::CreateRecord do
  around do |example|
    with_current_context(user: user) { example.run }
  end

  let(:user) { SpecSeed.user }

  def create_record_fixture(primary_count: 2)
    zone = create_dns_zone!(
      user: user,
      source: :internal_source,
      name: "create-record-#{SecureRandom.hex(4)}.example.test."
    )

    primary_count.times do
      create_dns_server_zone!(
        dns_zone: zone,
        dns_server: create_dns_server!(
          node: create_node!(name: "dns-create-record-#{SecureRandom.hex(3)}"),
          name: "ns-create-record-#{SecureRandom.hex(3)}"
        ),
        zone_type: :primary_type
      )
    end

    create_dns_server_zone!(
      dns_zone: zone,
      dns_server: create_dns_server!(
        node: create_node!(name: "dns-create-secondary-#{SecureRandom.hex(3)}"),
        name: "ns-create-secondary-#{SecureRandom.hex(3)}"
      ),
      zone_type: :secondary_type
    )

    zone
  end

  it 'creates enabled records on primary server zones and reloads each server' do
    zone = create_record_fixture
    record = create_dns_record!(dns_zone: zone, name: 'www', content: '192.0.2.55')

    chain, created = described_class.fire(record)

    expect(created).to eq(record)
    expect(tx_classes(chain)).to eq(
      [
        Transactions::DnsServerZone::CreateRecords,
        Transactions::DnsServer::Reload,
        Transactions::DnsServerZone::CreateRecords,
        Transactions::DnsServer::Reload,
        Transactions::Utils::NoOp
      ]
    )
    expect(
      tx_payloads(chain)
        .select { |payload| payload['records'] }
        .map { |payload| payload.fetch('records').first.fetch('id') }
    ).to eq([record.id, record.id])
    expect(
      tx_payloads(chain)
        .select { |payload| payload.has_key?('zone') }
        .map { |payload| payload.fetch('zone') }
    ).to eq([zone.name.delete_suffix('.'), zone.name.delete_suffix('.')])
  end

  it 'confirms disabled records immediately without runtime transactions' do
    zone = create_record_fixture
    record = create_dns_record!(
      dns_zone: zone,
      name: 'disabled',
      content: '192.0.2.56',
      enabled: false
    )

    chain, created = described_class.fire(record)

    expect(chain).to be_nil
    expect(created.reload.confirmed).to eq(:confirmed)
  end

  it 'confirms record logs and update tokens with the runtime change' do
    zone = create_record_fixture(primary_count: 1)
    record = create_dns_update_token_record!(
      dns_zone: zone,
      name: 'dynamic',
      content: '192.0.2.57'
    )

    chain, = described_class.fire(record)
    confirmations = confirmations_for(chain)

    expect(confirmations.find { |row| row.class_name == 'DnsRecord' }.confirm_type).to eq('create_type')
    expect(confirmations.find { |row| row.class_name == 'DnsRecordLog' }.confirm_type).to eq('just_create_type')
    expect(confirmations.find { |row| row.class_name == 'Token' }.confirm_type).to eq('just_create_type')
  end
end
