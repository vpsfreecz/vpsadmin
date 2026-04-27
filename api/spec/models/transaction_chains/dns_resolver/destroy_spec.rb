# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::DnsResolver::Destroy do
  around do |example|
    with_current_context(user: user) { example.run }
  end

  let(:user) { SpecSeed.user }

  def create_vps_on(node:, resolver:)
    pool = create_pool!(node: node, role: :hypervisor)
    dataset, dip = create_dataset_with_pool!(
      user: user,
      pool: pool,
      name: "resolver-destroy-#{SecureRandom.hex(4)}"
    )

    create_vps_for_dataset!(
      user: user,
      node: node,
      dataset_in_pool: dip,
      dns_resolver: resolver
    )
  end

  it 'reassigns VPSes using the resolver to suitable alternatives' do
    resolver = DnsResolver.create!(
      label: "resolver-destroy-#{SecureRandom.hex(4)}",
      addrs: '192.0.2.220',
      is_universal: true,
      location: nil,
      ip_version: 4
    )
    alternative = DnsResolver.create!(
      label: "resolver-alternative-#{SecureRandom.hex(4)}",
      addrs: '192.0.2.221',
      is_universal: false,
      location: SpecSeed.other_location,
      ip_version: 4
    )
    vps = create_vps_on(node: SpecSeed.other_node, resolver: resolver)

    chain, = described_class.fire(resolver)

    expect(tx_classes(chain)).to eq(
      [
        Transactions::Vps::DnsResolver,
        Transactions::Utils::NoOp
      ]
    )
    expect(tx_payload(chain, Transactions::Vps::DnsResolver, vps_id: vps.id)).to eq(
      'nameserver' => [alternative.addrs],
      'original' => [resolver.addrs]
    )
    expect(confirmations_for(chain).find { |row| row.class_name == 'DnsResolver' }.confirm_type).to eq(
      'just_destroy_type'
    )
  end

  it 'destroys unused resolvers immediately' do
    resolver = DnsResolver.create!(
      label: "resolver-unused-#{SecureRandom.hex(4)}",
      addrs: '192.0.2.230',
      is_universal: true,
      location: nil,
      ip_version: 4
    )

    chain, = described_class.fire(resolver)

    expect(chain).to be_nil
    expect(DnsResolver.where(id: resolver.id)).to be_empty
  end
end
