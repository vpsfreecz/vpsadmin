# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::DnsZone::DestroyRecord do
  around do |example|
    with_current_context(user: user) { example.run }
  end

  let(:user) { SpecSeed.user }

  def create_destroy_record_fixture(with_token: false)
    zone = create_dns_zone!(
      user: user,
      source: :internal_source,
      name: "destroy-record-#{SecureRandom.hex(4)}.example.test."
    )
    create_dns_server_zone!(
      dns_zone: zone,
      dns_server: create_dns_server!(node: SpecSeed.node, name: "ns-destroy-record-#{SecureRandom.hex(3)}"),
      zone_type: :primary_type
    )
    record =
      if with_token
        create_dns_update_token_record!(
          dns_zone: zone,
          name: 'www',
          content: '192.0.2.70'
        )
      else
        create_dns_record!(dns_zone: zone, name: 'www', content: '192.0.2.70')
      end

    record.update!(confirmed: DnsRecord.confirmed(:confirmed))
    record
  end

  it 'deletes enabled runtime records and reloads the DNS server' do
    record = create_destroy_record_fixture

    chain, = described_class.fire(record)

    expect(tx_classes(chain)).to eq(
      [
        Transactions::DnsServerZone::DeleteRecords,
        Transactions::DnsServer::Reload,
        Transactions::Utils::NoOp
      ]
    )
    expect(record.reload.confirmed).to eq(:confirm_destroy)
  end

  it 'confirms record destruction, log creation, and token removal' do
    record = create_destroy_record_fixture(with_token: true)

    chain, = described_class.fire(record)
    confirmations = confirmations_for(chain)

    expect(confirmations.find { |row| row.class_name == 'DnsRecord' }.confirm_type).to eq('destroy_type')
    expect(confirmations.find { |row| row.class_name == 'DnsRecordLog' }.confirm_type).to eq('just_create_type')
    expect(confirmations.find { |row| row.class_name == 'Token' }.confirm_type).to eq('just_destroy_type')
  end
end
