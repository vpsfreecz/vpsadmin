# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::Vps::Replace::Os do
  around do |example|
    with_current_context { example.run }
  end

  let(:user) { SpecSeed.user }

  before do
    allow(MailTemplate).to receive(:send_mail!).and_return(nil)
  end

  def ensure_user_cluster_resource!(user:, environment:, resource:, value:)
    cluster_resource = ClusterResource.find_by!(name: resource.to_s)
    record = UserClusterResource.find_or_initialize_by(
      user: user,
      environment: environment,
      cluster_resource: cluster_resource
    )

    record.value = value if record.new_record? || record.value.to_i < value
    record.save! if record.changed?
    record
  end

  def ensure_numeric_resources!(user:, environment:)
    {
      cpu: 32,
      memory: 64 * 1024,
      swap: 64 * 1024,
      diskspace: 256 * 1024
    }.each do |resource, value|
      ensure_user_cluster_resource!(
        user: user,
        environment: environment,
        resource: resource,
        value: value
      )
    end
  end

  def allocate_dip_diskspace!(dip, user:, value:)
    with_current_context do
      dip.allocate_resource!(
        :diskspace,
        value,
        user: user,
        confirmed: ClusterResourceUse.confirmed(:confirmed),
        admin_override: true
      )
    end
  end

  def allocate_vps_resources!(vps, user:, cpu: 2, memory: 2048, swap: 0)
    with_current_context do
      vps.allocate_resources(
        required: %i[cpu memory swap],
        optional: [],
        user: user,
        confirmed: ClusterResourceUse.confirmed(:confirmed),
        values: { cpu: cpu, memory: memory, swap: swap },
        admin_override: true
      )
    end
  end

  def seed_vps_features!(vps)
    VpsFeature::FEATURES.each do |name, feature|
      next unless feature.support?(vps.node)

      VpsFeature.find_or_create_by!(vps: vps, name: name) do |row|
        row.enabled = feature.default?
      end
    end
  end

  def create_network_interface!(vps, name:, kind: :veth_routed)
    NetworkInterface.create!(
      vps: vps,
      kind: kind,
      name: name
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
      user_editable: false,
      confirmed: Mount.confirmed(:confirmed),
      enabled: true,
      master_enabled: true
    )
  end

  def tx_payload(chain, klass)
    tx = transactions_for(chain).find { |row| Transaction.for_type(row.handle) == klass }
    JSON.parse(tx.input).fetch('input')
  end

  def create_replace_fixture(same_location: true, same_node: false)
    src_node = SpecSeed.node
    dst_location = same_location ? src_node.location : SpecSeed.other_location
    dst_node =
      if same_node
        src_node
      else
        create_node!(
          location: dst_location,
          role: :node,
          name: "replace-dst-#{SecureRandom.hex(3)}"
        )
      end
    src_pool = create_pool!(node: src_node, role: :hypervisor)
    src_pool.update!(migration_public_key: 'spec-src-pubkey')
    create_pool!(
      node: dst_node,
      role: :hypervisor,
      filesystem: "spec_hv_dst_#{SecureRandom.hex(4)}"
    )
    root_dataset, root_dip = create_dataset_with_pool!(
      user: user,
      pool: src_pool,
      name: "replace-root-#{SecureRandom.hex(4)}"
    )
    child_dataset, child_dip = create_dataset_with_pool!(
      user: user,
      pool: src_pool,
      parent: root_dataset,
      name: "child-#{SecureRandom.hex(4)}"
    )

    ensure_numeric_resources!(user: user, environment: src_node.location.environment)
    ensure_numeric_resources!(user: user, environment: dst_location.environment)
    allocate_dip_diskspace!(root_dip, user: user, value: 10_240)
    allocate_dip_diskspace!(child_dip, user: user, value: 10_240)

    vps = create_vps_for_dataset!(user: user, node: src_node, dataset_in_pool: root_dip)
    allocate_vps_resources!(vps, user: user)
    seed_vps_features!(vps)

    {
      src_node: src_node,
      dst_node: dst_node,
      src_pool: src_pool,
      root_dataset: root_dataset,
      root_dip: root_dip,
      child_dataset: child_dataset,
      child_dip: child_dip,
      vps: vps
    }
  end

  it 'uses local copy for same-node replace and omits remote send steps' do
    fixture = create_replace_fixture(same_node: true)
    vps = fixture.fetch(:vps)
    create_network_interface!(vps, name: 'eth0')

    chain, dst_vps = described_class.fire(
      vps,
      fixture.fetch(:dst_node),
      start: false,
      expiration_date: nil,
      reason: 'spec replace'
    )
    classes = tx_classes(chain)
    copy_payload = tx_payload(chain, Transactions::Vps::Copy)
    autostart_payload = tx_payload(chain, Transactions::Vps::Autostart)

    expect(classes).to include(
      Transactions::Vps::RecoverCleanup,
      Transactions::Vps::Copy,
      Transactions::Vps::PopulateConfig,
      Transactions::Vps::RemoveVeth,
      Transactions::Vps::Autostart
    )
    expect(classes).not_to include(
      Transactions::Pool::AuthorizeSendKey,
      Transactions::Vps::SendConfig,
      Transactions::Vps::SendRootfs,
      Transactions::Vps::SendState,
      Transactions::Vps::SendCleanup,
      Transactions::Vps::Start
    )
    expect(copy_payload.fetch('consistent')).to be(false)
    expect(copy_payload.fetch('network_interfaces')).to be(true)
    expect(copy_payload.fetch('as_dataset')).to eq(
      File.join(dst_vps.dataset_in_pool.pool.filesystem, dst_vps.dataset_in_pool.dataset.full_name)
    )
    expect(autostart_payload.fetch('new').fetch('enable')).to be(false)
    expect(autostart_payload.fetch('revert')).to be(false)
    expect(dst_vps).to be_persisted
  end

  it 'adds a keep-going destination start when start is true' do
    fixture = create_replace_fixture(same_node: true)
    vps = fixture.fetch(:vps)
    create_network_interface!(vps, name: 'eth0')

    chain, dst_vps = described_class.fire(
      vps,
      fixture.fetch(:dst_node),
      start: true,
      expiration_date: nil,
      reason: 'spec replace'
    )
    start_tx = transactions_for(chain).find do |tx|
      Transaction.for_type(tx.handle) == Transactions::Vps::Start && tx.vps_id == dst_vps.id
    end

    expect(start_tx).not_to be_nil
    expect(start_tx.reversible).to eq('keep_going')
  end

  it 'uses remote send steps for remote replace' do
    fixture = create_replace_fixture
    vps = fixture.fetch(:vps)
    netif = create_network_interface!(vps, name: 'eth0')
    create_ip_address!(
      network: SpecSeed.network_v4,
      location: fixture.fetch(:src_node).location,
      network_interface: netif,
      addr: "192.0.2.#{20 + SecureRandom.random_number(40)}"
    )

    chain, = described_class.fire(
      vps,
      fixture.fetch(:dst_node),
      start: true,
      expiration_date: nil,
      reason: 'remote replace'
    )
    classes = tx_classes(chain)
    payload = tx_payload(chain, Transactions::Vps::SendConfig)

    expect(classes).to include(
      Transactions::Pool::AuthorizeSendKey,
      Transactions::Vps::SendConfig,
      Transactions::Vps::SendRollbackConfig,
      Transactions::Vps::SendRootfs,
      Transactions::Vps::SendState,
      Transactions::Vps::SendCleanup
    )
    expect(payload.fetch('network_interfaces')).to be(true)
  end

  it 'skips replacement mail when the user has the mailer disabled' do
    fixture = create_replace_fixture(same_node: true)
    vps = fixture.fetch(:vps)
    vps.user.update!(mailer_enabled: false)

    allow(MailTemplate).to receive(:send_mail!)

    described_class.fire(
      vps,
      fixture.fetch(:dst_node),
      start: false,
      expiration_date: nil,
      reason: 'replace without mail'
    )

    expect(MailTemplate).not_to have_received(:send_mail!)
  end

  it 'marks the source as soft_delete, disables old resources, and schedules interface reassignment' do
    fixture = create_replace_fixture
    vps = fixture.fetch(:vps)
    netif = create_network_interface!(vps, name: 'eth0')
    create_ip_address!(
      network: SpecSeed.network_v4,
      location: fixture.fetch(:src_node).location,
      network_interface: netif,
      addr: "192.0.2.#{80 + SecureRandom.random_number(40)}"
    )

    chain, dst_vps = described_class.fire(
      vps,
      fixture.fetch(:dst_node),
      start: false,
      expiration_date: Time.now + 3600,
      reason: 'metadata replace'
    )
    state_change = ObjectState.where(class_name: 'Vps', row_id: vps.id).order(:id).last
    resource_disables = confirmations_for(chain).select do |row|
      row.class_name == 'ClusterResourceUse' &&
        row.confirm_type == 'edit_after_type' &&
        row.attr_changes.to_h['enabled'] == 0
    end
    netif_moves = confirmations_for(chain).select do |row|
      row.class_name == 'NetworkInterface' &&
        row.confirm_type == 'edit_after_type' &&
        row.attr_changes.to_h['vps_id'] == dst_vps.id
    end

    expect(state_change).not_to be_nil
    expect(state_change.state).to eq('soft_delete')
    expect(resource_disables).not_to be_empty
    expect(netif_moves.map(&:row_pks)).to include({ 'id' => netif.id })
    expect(dst_vps.dataset_in_pool.confirmed).to eq(:confirm_create)
    expect(dst_vps.datasets.where(name: fixture.fetch(:child_dataset).name)).to exist
  end

  it 'copies only mounts for the root dataset and cloned descendants' do
    fixture = create_replace_fixture
    vps = fixture.fetch(:vps)
    external_dataset, external_dip = create_dataset_with_pool!(
      user: user,
      pool: fixture.fetch(:src_pool),
      name: "external-#{SecureRandom.hex(4)}"
    )
    allocate_dip_diskspace!(external_dip, user: user, value: 10_240)

    mount_chain, = TransactionChains::Vps::MountDataset.fire(
      vps,
      fixture.fetch(:child_dataset),
      '/mnt/sub',
      mode: 'rw',
      enabled: true
    )
    mount_chain.release_locks
    create_mount!(vps: vps, dataset_in_pool: external_dip, dst: '/mnt/external')

    _chain, dst_vps = described_class.fire(
      vps,
      fixture.fetch(:dst_node),
      start: false,
      expiration_date: nil,
      reason: 'mount replace'
    )
    dst_mounts = dst_vps.mounts.order(:dst).to_a
    dst_child = dst_vps.datasets.find_by!(name: fixture.fetch(:child_dataset).name)
    dst_child_dip = DatasetInPool.find_by!(dataset: dst_child, pool: dst_vps.dataset_in_pool.pool)

    expect(dst_mounts.map(&:dst)).to include('/mnt/sub')
    expect(dst_mounts.map(&:dst)).not_to include('/mnt/external')
    expect(dst_mounts.find { |mnt| mnt.dst == '/mnt/sub' }.dataset_in_pool_id).to eq(dst_child_dip.id)
    expect(external_dataset).to be_persisted
  end
end
