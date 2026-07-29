# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::DnsResolver::Update do
  around do |example|
    with_current_context(user: user) { example.run }
  end

  let(:user) { SpecSeed.user }

  before do
    ensure_user_notification_templates!
    ensure_mailer_available!
    create_spec_event_route!(
      user: SpecSeed.admin,
      event_type: 'dns_resolver.updated',
      subject_scope: :visible
    )
  end

  def create_vps_on(node:, resolver:, hostname:)
    pool = create_pool!(node: node, role: :hypervisor)
    dataset, dip = create_dataset_with_pool!(
      user: user,
      pool: pool,
      name: hostname
    )

    create_vps_for_dataset!(
      user: user,
      node: node,
      dataset_in_pool: dip,
      hostname: hostname,
      dns_resolver: resolver
    ).tap do |vps|
      create_network_interface!(vps, name: 'eth0')
    end
  end

  it 'emits an uncorrelated fact for a synchronous resolver update' do
    resolver = DnsResolver.create!(
      label: "resolver-label-#{SecureRandom.hex(4)}",
      addrs: '192.0.2.199',
      is_universal: true,
      location: nil,
      ip_version: 4
    )

    chain, updated = described_class.fire(resolver, label: 'New resolver label')

    expect(chain).to be_nil
    expect(updated.reload.label).to eq('New resolver label')
    event = expect_resource_event!(:updated, resolver)
    expect(event.parameters['changed_fields']).to eq(['label'])
  end

  it 'updates resolver addresses on every VPS using the resolver' do
    resolver = DnsResolver.create!(
      label: "resolver-update-#{SecureRandom.hex(4)}",
      addrs: '192.0.2.200',
      is_universal: true,
      location: nil,
      ip_version: 4
    )
    vps = create_vps_on(
      node: SpecSeed.node,
      resolver: resolver,
      hostname: "resolver-address-#{SecureRandom.hex(4)}"
    )

    chain, updated = described_class.fire(resolver, addrs: '192.0.2.201')

    expect(updated.addrs).to eq('192.0.2.201')
    expect(tx_classes(chain)).to include(
      Transactions::Vps::DnsResolver,
      Transactions::Utils::NoOp
    )
    expect(tx_payload(chain, Transactions::Vps::DnsResolver, vps_id: vps.id)).to eq(
      'nameserver' => ['192.0.2.201'],
      'original' => ['192.0.2.200']
    )
    expect_deferred_event!(chain, 'vps.dns_resolver_changed')
    complete_chain_operation!(chain)

    event = expect_completed_event!('vps.dns_resolver_changed', user:)
    expect(event.vps).to eq(vps)
    expect(event.parameters).to include(
      'operation_id' => chain.id,
      'old_dns_resolver_addrs' => '192.0.2.200',
      'new_dns_resolver_addrs' => '192.0.2.201'
    )
    expect(confirmations_for(chain).find { |row| row.class_name == 'DnsResolver' }.attr_changes).to eq(
      'addrs' => '192.0.2.201'
    )
  end

  it 'moves only VPSes outside the new resolver scope to suitable resolvers' do
    resolver = DnsResolver.create!(
      label: "resolver-scope-#{SecureRandom.hex(4)}",
      addrs: '192.0.2.210',
      is_universal: true,
      location: nil,
      ip_version: 4
    )
    other_resolver = DnsResolver.create!(
      label: "resolver-other-#{SecureRandom.hex(4)}",
      addrs: '192.0.2.211',
      is_universal: false,
      location: SpecSeed.other_location,
      ip_version: 4
    )
    local_vps = create_vps_on(
      node: SpecSeed.node,
      resolver: resolver,
      hostname: "resolver-local-#{SecureRandom.hex(4)}"
    )
    remote_vps = create_vps_on(
      node: SpecSeed.other_node,
      resolver: resolver,
      hostname: "resolver-remote-#{SecureRandom.hex(4)}"
    )

    chain, = described_class.fire(
      resolver,
      is_universal: false,
      location_id: SpecSeed.location.id
    )

    expect(tx_classes(chain)).to include(
      Transactions::Vps::DnsResolver,
      Transactions::Utils::NoOp
    )
    expect(transactions_for(chain).select { |tx| tx.vps_id == local_vps.id }).to be_empty
    expect(tx_payload(chain, Transactions::Vps::DnsResolver, vps_id: remote_vps.id)).to eq(
      'nameserver' => [other_resolver.addrs],
      'original' => ['192.0.2.210']
    )
    expect_deferred_event!(chain, 'vps.dns_resolver_changed')
    complete_chain_operation!(chain)

    event = expect_completed_event!('vps.dns_resolver_changed', user:)
    expect(event.vps).to eq(remote_vps)
    expect(event.parameters).to include(
      'old_dns_resolver_addrs' => '192.0.2.210',
      'new_dns_resolver_addrs' => other_resolver.addrs
    )
  end
end
