# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::Dataset::Create do
  around do |example|
    with_current_context { example.run }
  end

  let(:user) { SpecSeed.user }

  def build_pending_dataset(name)
    Dataset.new(
      user: user,
      name: name,
      user_editable: true,
      user_create: true,
      user_destroy: true,
      confirmed: Dataset.confirmed(:confirm_create)
    )
  end

  def create_mount!(vps:, dataset_in_pool:, dst:)
    Mount.create!(
      vps: vps,
      dataset_in_pool: dataset_in_pool,
      dst: dst,
      mount_opts: '--bind',
      umount_opts: '-f',
      mount_type: 'bind',
      mode: 'rw',
      confirmed: Mount.confirmed(:confirmed),
      object_state: Mount.object_states[:active]
    )
  end

  def ensure_diskspace_resource!(user:, environment:, value: 1_000_000)
    resource = ClusterResource.find_by!(name: 'diskspace')
    record = UserClusterResource.find_or_initialize_by(
      user: user,
      environment: environment,
      cluster_resource: resource
    )
    record.value = value
    record.save! if record.changed?
    record
  end

  it 'creates a top-level dataset and plans diskspace allocation when quota is set' do
    pool = create_pool!(node: SpecSeed.node, role: :primary)
    seed_pool_dataset_properties!(pool)
    ensure_diskspace_resource!(user: user, environment: pool.node.location.environment)

    chain, created = described_class.fire(
      pool,
      nil,
      [build_pending_dataset("create-#{SecureRandom.hex(4)}")],
      {
        properties: { quota: 2048 },
        user: user,
        create_private: false
      }
    )
    created_dip = Array(created).last
    use = ClusterResourceUse.find_by!(class_name: 'DatasetInPool', row_id: created_dip.id)

    expect(tx_classes(chain)).to include(
      Transactions::Storage::CreateDataset,
      Transactions::Utils::NoOp
    )
    expect(created_dip.reload.confirmed).to eq(:confirm_create)
    expect(created_dip.dataset.reload.parent).to be_nil
    expect(use.value).to eq(2048)
    expect(confirmations_for(chain).map(&:class_name)).to include('ClusterResourceUse')
  end

  it 'creates each missing descendant segment and allocates refquota on the final dataset' do
    pool = create_pool!(node: SpecSeed.node, role: :primary, refquota_check: true)
    parent, parent_dip = create_dataset_with_pool!(
      user: user,
      pool: pool,
      name: "root-#{SecureRandom.hex(4)}"
    )
    ensure_diskspace_resource!(user: user, environment: pool.node.location.environment)

    chain, created = described_class.fire(
      pool,
      parent_dip,
      [
        build_pending_dataset('var'),
        build_pending_dataset('log')
      ],
      {
        properties: { refquota: 2048 },
        user: user,
        create_private: false
      }
    )
    created_dips = Array(created)
    leaf_dip = created_dips.last
    use = ClusterResourceUse.find_by!(class_name: 'DatasetInPool', row_id: leaf_dip.id)

    expect(tx_classes(chain).count(Transactions::Storage::CreateDataset)).to eq(2)
    expect(created_dips.map { |dip| dip.dataset.reload.full_name }).to eq(
      [
        "#{parent.full_name}/var",
        "#{parent.full_name}/var/log"
      ]
    )
    expect(use.value).to eq(2048)
  end

  it 'does not generate derived mounts when automount is disabled' do
    pool = create_pool!(node: SpecSeed.node, role: :primary)
    root, root_dip = create_dataset_with_pool!(
      user: user,
      pool: pool,
      name: "root-#{SecureRandom.hex(4)}"
    )
    vps = create_vps_for_dataset!(
      user: user,
      node: SpecSeed.node,
      dataset_in_pool: root_dip
    )
    create_mount!(vps: vps, dataset_in_pool: root_dip, dst: '/srv/data')

    without_automount_chain, without_automount_created = described_class.fire(
      pool,
      root_dip,
      [build_pending_dataset('manual')],
      {
        automount: false,
        properties: {},
        user: user,
        create_private: false
      }
    )
    without_automount_dip = Array(without_automount_created).last

    expect(tx_classes(without_automount_chain)).not_to include(Transactions::Vps::Mounts)
    expect(Mount.where(dataset_in_pool: without_automount_dip)).to be_empty
  end

  it 'generates derived mounts when automount is enabled' do
    pool = create_pool!(node: SpecSeed.node, role: :primary)
    root, root_dip = create_dataset_with_pool!(
      user: user,
      pool: pool,
      name: "root-#{SecureRandom.hex(4)}"
    )
    vps = create_vps_for_dataset!(
      user: user,
      node: SpecSeed.node,
      dataset_in_pool: root_dip
    )
    create_mount!(vps: vps, dataset_in_pool: root_dip, dst: '/srv/data')

    chain, created = described_class.fire(
      pool,
      root_dip,
      [build_pending_dataset('auto')],
      {
        automount: true,
        properties: {},
        user: user,
        create_private: false
      }
    )
    created_dip = Array(created).last
    derived_mount = Mount.find_by!(dataset_in_pool: created_dip)

    expect(tx_classes(chain)).to include(Transactions::Vps::Mounts)
    expect(derived_mount.dst).to eq('/srv/data/auto')
    expect(derived_mount.confirmed).to eq(:confirm_create)
  end
end
