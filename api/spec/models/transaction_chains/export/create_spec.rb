# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::Export::Create do
  around do |example|
    with_current_context(user: user) { example.run }
  end

  let(:user) { SpecSeed.user }

  def create_exportable_dataset(name: "export-create-#{SecureRandom.hex(4)}")
    pool = create_pool!(node: SpecSeed.node, role: :primary)
    dataset, dip = create_dataset_with_pool!(user: user, pool: pool, name: name)
    export_network = create_private_network!(location: pool.node.location)
    create_ipv4_address_in_network!(network: export_network, location: pool.node.location)
    [dataset, dip]
  end

  it 'creates export runtime, hosts, and enable transactions for primary datasets' do
    dataset, dip = create_exportable_dataset
    vps = create_vps_for_dataset!(user: user, node: dip.pool.node, dataset_in_pool: dip)
    netif = create_network_interface!(vps, name: 'eth0')
    exported_ip = create_ip_address!(network_interface: netif)

    chain, export = described_class.fire(dataset, all_vps: true, enabled: true, threads: 16)

    expect(tx_classes(chain)).to eq(
      [
        Transactions::Export::Create,
        Transactions::Export::AddHosts,
        Transactions::Export::Enable
      ]
    )
    expect(export).to be_persisted
    expect(export.dataset_in_pool).to eq(dip)
    expect(export.threads).to eq(16)
    expect(export.enabled).to be(true)
    expect(export.all_vps).to be(true)
    expect(export.network_interface).to be_present
    expect(export.network_interface.name).to eq('eth0')
    expect(export.ip_address).to be_present
    expect(export.ip_address.network_interface_id).to eq(export.network_interface.id)
    expect(export.export_hosts.pluck(:ip_address_id)).to eq([exported_ip.id])
    expect(chain.concern_type).to eq('chain_affect')
    expect(chain.transaction_chain_concerns.pluck(:class_name, :row_id)).to include(['Export', export.id])
    expect(chain.locks.map { |lock| [lock.resource, lock.row_id] }).to include(
      ['DatasetInPool', dip.id],
      ['Export', export.id],
      ['NetworkInterface', export.network_interface.id],
      ['IpAddress', export.ip_address.id]
    )
  end

  it 'uses a snapshot clone and sets expiration date when exporting a snapshot' do
    dataset, dip = create_exportable_dataset(name: "export-snapshot-#{SecureRandom.hex(4)}")
    snapshot, sip = create_snapshot!(dataset: dataset, dip: dip, name: 'snap-1')

    chain, export = described_class.fire(dataset, snapshot: snapshot, enabled: false)

    expect(tx_classes(chain)).to include(
      Transactions::Storage::CloneSnapshot,
      Transactions::Export::Create
    )
    expect(export.snapshot_in_pool_clone).to be_present
    expect(export.snapshot_in_pool_clone.snapshot_in_pool).to eq(sip)
    expect(export.expiration_date).to be_within(5.seconds).of(3.days.from_now)
    expect(export.path).to include(dataset.full_name)
    expect(export.path).to include(snapshot.created_at.iso8601)
  end

  it 'raises OperationNotSupported for datasets on unsupported pools' do
    pool = create_pool!(node: SpecSeed.node, role: :hypervisor)
    dataset, = create_dataset_with_pool!(
      user: user,
      pool: pool,
      name: "export-unsupported-#{SecureRandom.hex(4)}"
    )

    expect do
      described_class.fire(dataset)
    end.to raise_error(
      VpsAdmin::API::Exceptions::OperationNotSupported,
      /cannot be exported/
    )
  end
end
