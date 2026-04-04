# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::Dataset::Migrate do
  around do |example|
    with_current_context do
      example.run
    end
  end

  let(:user) { SpecSeed.user }

  def create_primary_pool_pair(same_node: false)
    src_node = SpecSeed.node
    dst_node =
      if same_node
        src_node
      else
        create_node!(location: src_node.location, role: :storage, name: "dst-#{SecureRandom.hex(3)}")
      end

    src_pool = create_pool!(node: src_node, role: :primary)
    src_pool.update!(migration_public_key: 'spec-src-pubkey')
    dst_pool = create_pool!(
      node: dst_node,
      role: :primary,
      filesystem: "spec_primary_dst_#{SecureRandom.hex(4)}"
    )
    dst_pool.update!(migration_public_key: 'spec-dst-pubkey')

    create_port_reservations!(node: dst_node)
    [src_pool, dst_pool]
  end

  def create_dataset_subtree!(pool:)
    root, root_dip = create_dataset_with_pool!(
      user: user,
      pool: pool,
      name: "migrate-root-#{SecureRandom.hex(4)}",
      properties: { compression: false }
    )
    child, child_dip = create_dataset_with_pool!(
      user: user,
      pool: pool,
      name: "child-#{SecureRandom.hex(4)}",
      parent: root,
      properties: { compression: false }
    )

    [root, root_dip, child, child_dip]
  end

  def confirmation_changes(chain, class_name)
    confirmations_for(chain).select { |row| row.class_name == class_name }.map do |row|
      [row.row_pks, row.attr_changes]
    end
  end

  it 'refuses migration when the source pool has snapshot clones' do
    src_pool, dst_pool = create_primary_pool_pair
    dataset, src_dip = create_dataset_with_pool!(user: user, pool: src_pool, name: "clones-#{SecureRandom.hex(4)}")
    _, sip = create_snapshot!(dataset: dataset, dip: src_dip, name: 'snap-1')

    SnapshotInPoolClone.create!(
      snapshot_in_pool: sip,
      user_namespace_map: create_user_namespace_map!(user: user),
      name: "#{sip.snapshot_id}-clone.snapshot",
      state: :active
    )

    expect do
      described_class.fire(src_dip, dst_pool, send_mail: false)
    end.to raise_error(
      VpsAdmin::API::Exceptions::OperationNotSupported,
      'unable to migrate dataset with existing snapshot clones'
    )
  end

  it 'uses snapshot and transfer transactions for non-rsync migration' do
    src_pool, dst_pool = create_primary_pool_pair
    _root, root_dip, = create_dataset_subtree!(pool: src_pool)

    chain, = described_class.fire(root_dip, dst_pool, send_mail: false)
    classes = tx_classes(chain)

    expect(classes.count(Transactions::Storage::CreateDataset)).to eq(2)
    expect(classes.count(Transactions::Storage::SetDataset)).to eq(4)
    expect(classes.count(Transactions::Storage::CreateSnapshot)).to eq(4)
    expect(classes.count(Transactions::Storage::Recv)).to eq(4)
    expect(classes.count(Transactions::Storage::Send)).to eq(4)
    expect(classes.count(Transactions::Storage::RecvCheck)).to eq(4)
    expect(classes.count(Transactions::Queue::Reserve)).to eq(2)
    expect(classes.count(Transactions::Queue::Release)).to eq(2)
    expect(classes).to include(
      Transactions::Storage::SetCanmount,
      Transactions::Storage::DestroyDataset
    )
  end

  it 'uses rsync transactions and detaches backup heads instead of send/recv' do
    src_pool, dst_pool = create_primary_pool_pair
    root, root_dip, = create_dataset_subtree!(pool: src_pool)
    backup_pool = create_pool!(
      node: create_node!(location: src_pool.node.location, role: :storage),
      role: :backup
    )
    backup_dip = attach_dataset_to_pool!(dataset: root, pool: backup_pool)
    tree = create_tree!(dip: backup_dip, index: 0, head: true)
    branch = create_branch!(tree: tree, name: 'head', head: true)

    chain, = described_class.fire(root_dip, dst_pool, rsync: true, send_mail: false)
    classes = tx_classes(chain)
    rsync_txs = transactions_for(chain).select do |t|
      Transaction.for_type(t.handle) == Transactions::Storage::RsyncDataset
    end
    auth_txs = transactions_for(chain).select do |t|
      Transaction.for_type(t.handle) == Transactions::Pool::AuthorizeRsyncKey
    end
    revoke_txs = transactions_for(chain).select do |t|
      Transaction.for_type(t.handle) == Transactions::Pool::RevokeRsyncKey
    end

    expect(classes.count(Transactions::Storage::RsyncDataset)).to eq(4)
    expect(classes.count(Transactions::Pool::AuthorizeRsyncKey)).to eq(1)
    expect(classes.count(Transactions::Pool::RevokeRsyncKey)).to eq(1)
    expect(classes).not_to include(
      Transactions::Pool::AuthorizeSendKey,
      Transactions::Storage::Recv,
      Transactions::Storage::Send,
      Transactions::Storage::RecvCheck,
      Transactions::Storage::SetCanmount
    )
    expect(classes.index(Transactions::Pool::AuthorizeRsyncKey)).to be < classes.index(Transactions::Queue::Reserve)
    expect(classes.rindex(Transactions::Pool::RevokeRsyncKey)).to be > classes.rindex(Transactions::Storage::RsyncDataset)
    expect(auth_txs.map(&:node_id).uniq).to eq([src_pool.node_id])
    expect(revoke_txs.map(&:node_id).uniq).to eq([src_pool.node_id])
    expect(rsync_txs.map(&:queue).uniq).to eq(['zfs_recv'])
    expect(rsync_txs.map(&:node_id).uniq).to eq([dst_pool.node_id])
    expect(confirmation_changes(chain, 'DatasetTree')).to include(
      [{ 'id' => tree.id }, { 'head' => 0 }]
    )
    expect(confirmation_changes(chain, 'Branch')).to include(
      [{ 'id' => branch.id }, { 'head' => 0 }]
    )
  end

  it 'destroys exports on the source pool for same-node pool migration' do
    src_pool, dst_pool = create_primary_pool_pair(same_node: true)
    _dataset, src_dip = create_dataset_with_pool!(
      user: user,
      pool: src_pool,
      name: "exports-#{SecureRandom.hex(4)}",
      properties: { compression: false }
    )
    export, = create_export_for_dataset!(dataset_in_pool: src_dip)
    ExportHost.create!(
      export: export,
      ip_address: create_ip_address!(location: src_pool.node.location),
      rw: export.rw,
      sync: export.sync,
      subtree_check: export.subtree_check,
      root_squash: export.root_squash
    )

    chain, = described_class.fire(src_dip, dst_pool, send_mail: false)
    classes = tx_classes(chain)

    expect(export.host_ip_address).to be_present
    expect(classes).to include(
      Transactions::Export::Disable,
      Transactions::Export::DelHosts,
      Transactions::Export::Destroy,
      Transactions::Export::Create,
      Transactions::Export::AddHosts,
      Transactions::Export::Enable
    )
    expect(classes.index(Transactions::Export::Disable)).to be < classes.index(Transactions::Export::DelHosts)
    expect(classes.index(Transactions::Export::DelHosts)).to be < classes.index(Transactions::Export::Destroy)
    expect(classes.index(Transactions::Export::Destroy)).to be < classes.index(Transactions::Export::Create)
  end

  it 'disables the source export, recreates it on the destination, and destroys it afterwards on cross-node migration' do
    src_pool, dst_pool = create_primary_pool_pair
    _dataset, src_dip = create_dataset_with_pool!(
      user: user,
      pool: src_pool,
      name: "exports-#{SecureRandom.hex(4)}",
      properties: { compression: false }
    )
    create_export_for_dataset!(dataset_in_pool: src_dip)

    chain, = described_class.fire(src_dip, dst_pool, send_mail: false)
    classes = tx_classes(chain)

    expect(classes).to include(
      Transactions::Export::Disable,
      Transactions::Export::Create,
      Transactions::Export::AddHosts,
      Transactions::Export::Enable,
      Transactions::Export::Destroy
    )
    expect(classes.index(Transactions::Export::Disable)).to be < classes.index(Transactions::Export::Create)
    expect(classes.index(Transactions::Export::Create)).to be < classes.rindex(Transactions::Export::Destroy)
  end

  it 'keeps the logical destroy path but skips dataset destruction when cleanup_data is false' do
    src_pool, dst_pool = create_primary_pool_pair
    _root, root_dip, = create_dataset_subtree!(pool: src_pool)

    chain, = described_class.fire(root_dip, dst_pool, cleanup_data: false, send_mail: false)
    classes = tx_classes(chain)
    dataset_destroy_confirmations = confirmations_for(chain).select do |row|
      row.class_name == 'DatasetInPool' && row.confirm_type == 'destroy_type'
    end

    expect(dataset_destroy_confirmations).not_to be_empty
    expect(classes).not_to include(Transactions::Storage::DestroyDataset)
  end

  it 'stops and restarts VPSes that have mounted exports around export migration' do
    src_pool, dst_pool = create_primary_pool_pair
    _dataset, src_dip = create_dataset_with_pool!(
      user: user,
      pool: src_pool,
      name: "exports-#{SecureRandom.hex(4)}",
      properties: { compression: false }
    )
    export, = create_export_for_dataset!(dataset_in_pool: src_dip)

    vps_pool = create_pool!(node: src_pool.node, role: :hypervisor)
    _mount_dataset, mount_dip = create_dataset_with_pool!(
      user: user,
      pool: vps_pool,
      name: "mounted-vps-#{SecureRandom.hex(4)}"
    )
    mounted_vps = create_vps_for_dataset!(user: user, node: src_pool.node, dataset_in_pool: mount_dip)
    set_vps_running!(mounted_vps)
    ExportMount.create!(
      export: export,
      vps: mounted_vps,
      mountpoint: '/mnt/export',
      nfs_version: '4.2'
    )

    chain, = described_class.fire(src_dip, dst_pool, restart_vps: true, send_mail: false)
    classes = tx_classes(chain)

    expect(classes).to include(Transactions::Vps::Stop, Transactions::Vps::Start)
    expect(classes.index(Transactions::Vps::Stop)).to be < classes.index(Transactions::Export::Disable)
    expect(classes.rindex(Transactions::Vps::Start)).to be > classes.index(Transactions::Export::Enable)
  end
end
