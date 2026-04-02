# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::Vps::Migrate do
  around do |example|
    with_current_context do
      example.run
    end
  end

  let(:user) { SpecSeed.user }

  def create_vps_migration_fixture
    src_node = SpecSeed.node
    dst_node = create_node!(location: src_node.location, role: :node, name: "dst-#{SecureRandom.hex(3)}")
    src_pool = create_pool!(node: src_node, role: :hypervisor)
    src_pool.update!(migration_public_key: 'spec-pubkey')
    create_pool!(node: dst_node, role: :hypervisor, filesystem: "spec_hv_dst_#{SecureRandom.hex(4)}")
    dataset, dip = create_dataset_with_pool!(user: user, pool: src_pool, name: "vps-migrate-#{SecureRandom.hex(4)}")
    vps = create_vps_for_dataset!(user: user, node: src_node, dataset_in_pool: dip)

    [dataset, dip, vps, dst_node]
  end

  it 'returns OsToOs for vpsadminos to vpsadminos migrations' do
    _dataset, _dip, vps, dst_node = create_vps_migration_fixture

    expect(described_class.chain_for(vps, dst_node)).to eq(TransactionChains::Vps::Migrate::OsToOs)
  end

  it 'rejects unsupported hypervisor combinations' do
    _dataset, _dip, vps, = create_vps_migration_fixture
    openvz_node = create_node!(
      location: SpecSeed.node.location,
      role: :node,
      hypervisor_type: :openvz,
      name: "openvz-#{SecureRandom.hex(3)}"
    )

    expect do
      described_class.chain_for(vps, openvz_node)
    end.to raise_error(
      VpsAdmin::API::Exceptions::OperationNotSupported,
      /Migration from vpsadminos to openvz is not supported/
    )
  end

  it 'rejects VPS migrations when the source subtree has snapshot clones' do
    dataset, dip, vps, dst_node = create_vps_migration_fixture
    _, sip = create_snapshot!(dataset: dataset, dip: dip, name: 'snap-1')

    SnapshotInPoolClone.create!(
      snapshot_in_pool: sip,
      user_namespace_map: create_user_namespace_map!(user: user),
      name: "#{sip.snapshot_id}-clone.snapshot",
      state: :active
    )

    expect do
      described_class.chain_for(vps, dst_node).fire(
        vps,
        dst_node,
        maintenance_window: false,
        send_mail: false
      )
    end.to raise_error(
      VpsAdmin::API::Exceptions::OperationNotSupported,
      'unable to migrate VPS with existing snapshot clones'
    )
  end

  it 'queues the core os-to-os migration subsequence' do
    _dataset, _dip, vps, dst_node = create_vps_migration_fixture
    set_vps_running!(vps)

    chain, = described_class.chain_for(vps, dst_node).fire(
      vps,
      dst_node,
      maintenance_window: false,
      send_mail: false
    )
    classes = tx_classes(chain)

    expect(classes).to include(
      Transactions::Pool::AuthorizeSendKey,
      Transactions::Vps::SendConfig,
      Transactions::Queue::Reserve,
      Transactions::Vps::SendRootfs,
      Transactions::Vps::Stop,
      Transactions::Vps::SendState,
      Transactions::Vps::Start,
      Transactions::Queue::Release,
      Transactions::Vps::SendCleanup,
      Transactions::Vps::RemoveConfig
    )
    expect(classes.index(Transactions::Pool::AuthorizeSendKey)).to be < classes.index(Transactions::Vps::SendConfig)
    expect(classes.index(Transactions::Vps::SendConfig)).to be < classes.index(Transactions::Vps::SendRootfs)
    expect(classes.index(Transactions::Vps::SendRootfs)).to be < classes.index(Transactions::Vps::SendState)
    expect(classes.index(Transactions::Vps::SendState)).to be < classes.index(Transactions::Vps::SendCleanup)
    expect(classes.rindex(Transactions::Queue::Release)).to be < classes.index(Transactions::Vps::SendCleanup)
  end
end
