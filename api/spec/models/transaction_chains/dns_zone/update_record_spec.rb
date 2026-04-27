# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::DnsZone::UpdateRecord do
  around do |example|
    with_current_context(user: user) { example.run }
  end

  let(:user) { SpecSeed.user }

  def create_update_record_fixture(enabled: true)
    zone = create_dns_zone!(
      user: user,
      source: :internal_source,
      name: "update-record-#{SecureRandom.hex(4)}.example.test."
    )
    create_dns_server_zone!(
      dns_zone: zone,
      dns_server: create_dns_server!(node: SpecSeed.node, name: "ns-update-record-#{SecureRandom.hex(3)}"),
      zone_type: :primary_type
    )
    record = create_dns_record!(
      dns_zone: zone,
      name: 'www',
      content: '192.0.2.60',
      ttl: 3600,
      enabled: enabled
    )
    record.update!(confirmed: DnsRecord.confirmed(:confirmed))

    [zone, record]
  end

  it 'updates enabled records and reloads the DNS server' do
    _zone, record = create_update_record_fixture
    record.assign_attributes(content: '192.0.2.61', ttl: 7200)

    chain, updated = described_class.fire(record)

    expect(updated.reload.content).to eq('192.0.2.61')
    expect(tx_classes(chain)).to eq(
      [
        Transactions::DnsServerZone::UpdateRecords,
        Transactions::DnsServer::Reload,
        Transactions::Utils::NoOp
      ]
    )
    expect(tx_payload(chain, Transactions::DnsServerZone::UpdateRecords).fetch('records').first).to include(
      'new' => include('content' => '192.0.2.61', 'ttl' => 7200),
      'original' => include('content' => '192.0.2.60', 'ttl' => 3600)
    )
  end

  it 'deletes runtime records when disabling an enabled record' do
    _zone, record = create_update_record_fixture
    record.enabled = false

    chain, = described_class.fire(record)

    expect(tx_classes(chain)).to include(
      Transactions::DnsServerZone::DeleteRecords,
      Transactions::DnsServer::Reload
    )
  end

  it 'creates runtime records when enabling a disabled record' do
    _zone, record = create_update_record_fixture(enabled: false)
    record.enabled = true

    chain, = described_class.fire(record)

    expect(tx_classes(chain)).to include(
      Transactions::DnsServerZone::CreateRecords,
      Transactions::DnsServer::Reload
    )
  end

  it 'saves disabled-to-disabled edits without runtime transactions' do
    _zone, record = create_update_record_fixture(enabled: false)
    record.content = '192.0.2.62'

    chain, updated = described_class.fire(record)

    expect(chain).to be_nil
    expect(updated.reload.content).to eq('192.0.2.62')
  end

  it 'confirms old record values with edit_before' do
    _zone, record = create_update_record_fixture
    record.assign_attributes(content: '192.0.2.63', ttl: 7200)

    chain, = described_class.fire(record)
    confirmation = confirmations_for(chain).find { |row| row.class_name == 'DnsRecord' }

    expect(confirmation.confirm_type).to eq('edit_before_type')
    expect(confirmation.attr_changes).to include(
      'content' => '192.0.2.60',
      'ttl' => 3600
    )
  end
end
