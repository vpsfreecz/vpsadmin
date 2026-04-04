# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::Vps::Migrate::MountMigrator do
  around do |example|
    with_current_context do
      example.run
    end
  end

  let(:user) { SpecSeed.user }

  def create_vps_fixture
    src_node = SpecSeed.node
    dst_node = create_node!(
      location: src_node.location,
      role: :node,
      name: "dst-#{SecureRandom.hex(3)}"
    )
    src_pool = create_pool!(node: src_node, role: :hypervisor)
    dst_pool = create_pool!(
      node: dst_node,
      role: :hypervisor,
      filesystem: "spec_hv_dst_#{SecureRandom.hex(4)}"
    )
    root_dataset, src_root_dip = create_dataset_with_pool!(
      user: user,
      pool: src_pool,
      name: "mount-root-#{SecureRandom.hex(4)}"
    )
    _dst_root_dataset, dst_root_dip = create_dataset_with_pool!(
      user: user,
      pool: dst_pool,
      name: root_dataset.name
    )
    child_dataset, src_child_dip = create_dataset_with_pool!(
      user: user,
      pool: src_pool,
      parent: root_dataset,
      name: "mount-child-#{SecureRandom.hex(4)}"
    )
    _dst_child_dataset, dst_child_dip = create_dataset_with_pool!(
      user: user,
      pool: dst_pool,
      parent: dst_root_dip.dataset,
      name: child_dataset.name
    )
    src_vps = create_vps_for_dataset!(user: user, node: src_node, dataset_in_pool: src_root_dip)
    dst_vps = create_vps_for_dataset!(user: user, node: dst_node, dataset_in_pool: dst_root_dip)
    chain = build_transaction_chain!(name: 'mount-migrator-spec')
    migrator = described_class.new(chain, src_vps, dst_vps)
    migrator.datasets = [[src_root_dip, dst_root_dip], [src_child_dip, dst_child_dip]]

    {
      chain: chain,
      src_node: src_node,
      dst_node: dst_node,
      src_vps: src_vps,
      dst_vps: dst_vps,
      src_root_dip: src_root_dip,
      dst_root_dip: dst_root_dip,
      src_child_dip: src_child_dip,
      dst_child_dip: dst_child_dip,
      migrator: migrator
    }
  end

  def create_mount!(vps:, dataset_in_pool:, snapshot_in_pool: nil, dst: '/mnt/data')
    Mount.create!(
      vps: vps,
      dataset_in_pool: dataset_in_pool,
      snapshot_in_pool: snapshot_in_pool,
      dst: dst,
      mount_opts: '--bind',
      umount_opts: '-f',
      mount_type: 'bind',
      mode: 'rw',
      enabled: true,
      confirmed: Mount.confirmed(:confirmed),
      object_state: Mount.object_states[:active]
    )
  end

  it 'remaps subdataset bind mounts to the destination dataset' do
    fixture = create_vps_fixture
    mount = create_mount!(
      vps: fixture.fetch(:src_vps),
      dataset_in_pool: fixture.fetch(:src_child_dip),
      dst: '/mnt/sub'
    )

    changes = fixture.fetch(:migrator).send(:migrate_mine_mount, mount)

    expect(mount.reload.vps_id).to eq(fixture.fetch(:dst_vps).id)
    expect(mount.dataset_in_pool_id).to eq(fixture.fetch(:dst_child_dip).id)
    expect(changes.fetch(mount)).to include(
      dataset_in_pool_id: fixture.fetch(:src_child_dip).id,
      snapshot_in_pool_id: nil
    )
  end

  it 'remaps subdataset snapshot mounts to the destination snapshot in pool' do
    fixture = create_vps_fixture
    snapshot, src_sip = create_snapshot!(
      dataset: fixture.fetch(:src_child_dip).dataset,
      dip: fixture.fetch(:src_child_dip),
      name: 'snap-1'
    )
    dst_sip = mirror_snapshot!(snapshot: snapshot, dip: fixture.fetch(:dst_child_dip))
    mount = create_mount!(
      vps: fixture.fetch(:src_vps),
      dataset_in_pool: fixture.fetch(:src_child_dip),
      snapshot_in_pool: src_sip,
      dst: '/mnt/snap'
    )
    src_sip.update!(mount: mount)

    changes = fixture.fetch(:migrator).send(:migrate_mine_mount, mount)

    expect(src_sip.reload.mount_id).to be_nil
    expect(dst_sip.reload.mount_id).to eq(mount.id)
    expect(mount.reload.snapshot_in_pool_id).to eq(dst_sip.id)
    expect(changes.fetch(mount)).to include(
      dataset_in_pool_id: fixture.fetch(:src_child_dip).id,
      snapshot_in_pool_id: src_sip.id
    )
    expect(changes.fetch(src_sip)).to include(mount_id: mount.id)
    expect(changes.fetch(dst_sip)).to include(mount_id: nil)
  end

  it 'marks matching mounts for confirm-destroy' do
    fixture = create_vps_fixture
    primary_pool = create_pool!(
      node: fixture.fetch(:src_node),
      role: :primary,
      filesystem: "spec_primary_#{SecureRandom.hex(4)}"
    )
    _primary_dataset, primary_dip = create_dataset_with_pool!(
      user: user,
      pool: primary_pool,
      name: "mount-primary-#{SecureRandom.hex(4)}"
    )
    mount = create_mount!(
      vps: fixture.fetch(:src_vps),
      dataset_in_pool: primary_dip,
      dst: '/mnt/primary'
    )
    migrator = described_class.new(
      fixture.fetch(:chain),
      fixture.fetch(:src_vps),
      fixture.fetch(:dst_vps)
    )

    migrator.delete_mine_if { |candidate| candidate.id == mount.id }

    expect(mount.reload.confirmed).to eq(:confirm_destroy)
    expect(migrator.instance_variable_get(:@my_deleted)).to contain_exactly(mount)
  end

  it 'rejects mounts that would become remote after migration' do
    fixture = create_vps_fixture
    _extra_dataset, extra_dip = create_dataset_with_pool!(
      user: user,
      pool: fixture.fetch(:src_root_dip).pool,
      name: "mount-extra-#{SecureRandom.hex(4)}"
    )
    mount = create_mount!(
      vps: fixture.fetch(:src_vps),
      dataset_in_pool: extra_dip,
      dst: '/mnt/extra'
    )

    expect do
      fixture.fetch(:migrator).send(:migrate_mine_mount, mount)
    end.to raise_error(RuntimeError, 'remote mounts not supported')
  end
end
