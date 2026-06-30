# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::Vps::Replace::Os do
  around do |example|
    with_current_context { example.run }
  end

  let(:user) { SpecSeed.user }

  before do
    allow(NotificationTemplate).to receive(:send_email!).and_return(nil)
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

  def tx_payloads_for(chain, klass)
    transactions_for(chain)
      .select { |row| Transaction.for_type(row.handle) == klass }
      .map { |row| JSON.parse(row.input).fetch('input') }
  end

  def expect_snapshot_reference(payload, snapshot)
    expect(payload).to include(
      'id' => snapshot.id,
      'name' => snapshot.name,
      'confirmed' => snapshot.confirmed.to_s
    )
    expect(payload.fetch('name')).to match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2} \(unconfirmed\)\z/)
  end

  def register_daily_backup_plan!(dip)
    create_daily_backup_env_plan!(environment: dip.pool.node.location.environment)
    VpsAdmin::API::DatasetPlans.plans[:daily_backup].register(dip)
  end

  def with_dataset_create_hook(callback)
    create_hooks = HaveAPI::Hooks.hooks.fetch(DatasetInPool).fetch(:create)
    original_listeners = create_hooks.fetch(:listeners)

    create_hooks[:listeners] = [callback]
    yield
  ensure
    create_hooks[:listeners] = original_listeners
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
    create_port_reservations!(node: dst_node)
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
    replace_snapshot = Snapshot.find_by!(
      dataset_id: fixture.fetch(:root_dataset).id,
      label: "Created for VPS replace #{vps.id} -> #{dst_vps.id}"
    )
    expect_snapshot_reference(copy_payload.fetch('from_snapshot'), replace_snapshot)
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

    chain, dst_vps = described_class.fire(
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
    expect(payload.fetch('snapshots')).to be(false)
    replace_snapshot = Snapshot.find_by!(
      dataset_id: fixture.fetch(:root_dataset).id,
      label: "Created for VPS replace #{vps.id} -> #{dst_vps.id}"
    )
    expect_snapshot_reference(payload.fetch('from_snapshot'), replace_snapshot)
  end

  it 'suppresses replacement mail when default notifications are muted' do
    fixture = create_replace_fixture(same_node: true)
    vps = fixture.fetch(:vps)
    mute_default_notifications_for!(vps.user)

    allow(NotificationTemplate).to receive(:send_email!)

    chain, dst_vps = described_class.fire(
      vps,
      fixture.fetch(:dst_node),
      start: false,
      expiration_date: nil,
      reason: 'replace without mail'
    )
    event = Event.where(event_type: 'vps.replaced').sole

    expect(event).to be_suppressed_routing_state
    expect(event.vps).to eq(vps)
    expect(event.source).to eq(dst_vps)
    expect(event.parameters).to include(
      'original_vps_id' => vps.id,
      'new_vps_id' => dst_vps.id,
      'reason' => 'replace without mail'
    )
    expect(tx_classes(chain)).not_to include(Transactions::EventDelivery::Notify)
    expect(NotificationTemplate).not_to have_received(:send_email!)
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

  it 'backs up replace snapshots, moves backup datasets, and rewires backup plans' do
    fixture = create_replace_fixture(same_node: true)
    backup_pool = create_pool!(
      node: SpecSeed.other_node,
      role: :backup,
      filesystem: "spec_backup_#{SecureRandom.hex(4)}"
    )
    create_port_reservations!(node: backup_pool.node)
    root_backup = attach_dataset_to_pool!(dataset: fixture.fetch(:root_dataset), pool: backup_pool)
    child_backup = attach_dataset_to_pool!(dataset: fixture.fetch(:child_dataset), pool: backup_pool)
    tree = create_tree!(dip: root_backup, index: 0, head: true)
    branch = create_branch!(tree: tree, name: 'existing-head', head: true)
    snap1, = create_snapshot!(dataset: fixture.fetch(:root_dataset), dip: fixture.fetch(:root_dip), name: 'snap-1')
    snap2, = create_snapshot!(dataset: fixture.fetch(:root_dataset), dip: fixture.fetch(:root_dip), name: 'snap-2')

    snap1_backup_sip = mirror_snapshot!(snapshot: snap1, dip: root_backup)
    attach_snapshot_to_branch!(sip: snap1_backup_sip, branch: branch)
    register_daily_backup_plan!(fixture.fetch(:root_dip))

    chain, dst_vps = described_class.fire(
      fixture.fetch(:vps),
      fixture.fetch(:dst_node),
      start: false,
      expiration_date: nil,
      reason: 'backup preserving replace'
    )
    classes = tx_classes(chain)
    dst_root = dst_vps.dataset_in_pool
    dst_child = DatasetInPool.find_by!(
      dataset: dst_vps.datasets.find_by!(name: fixture.fetch(:child_dataset).name),
      pool: dst_root.pool
    )
    rename_payloads = tx_payloads_for(chain, Transactions::Storage::RenameDataset)
    create_snapshot_payload = tx_payloads_for(chain, Transactions::Storage::CreateSnapshots).first
    confirmations = confirmations_for(chain).map do |row|
      [row.class_name, row.row_pks, row.attr_changes, row.confirm_type]
    end

    expect(classes.index(Transactions::Storage::CreateSnapshots)).to be < classes.index(Transactions::Vps::Copy)
    expect(classes).to include(
      Transactions::Storage::Send,
      Transactions::Storage::Recv,
      Transactions::Storage::RecvCheck,
      Transactions::Storage::RenameDataset,
      Transactions::Storage::CloneSnapshotName
    )
    expect(classes).not_to include(Transactions::Storage::LocalSend)
    expect(create_snapshot_payload).not_to have_key('name')
    expect(create_snapshot_payload).not_to have_key('created_at')
    expect(rename_payloads).to include(
      'pool_fs' => backup_pool.filesystem,
      'old_name' => fixture.fetch(:root_dataset).full_name,
      'new_name' => dst_root.dataset.full_name
    )
    expect(rename_payloads).not_to include(
      'pool_fs' => backup_pool.filesystem,
      'old_name' => fixture.fetch(:child_dataset).full_name,
      'new_name' => dst_child.dataset.full_name
    )

    replace_snapshots = Snapshot.where(label: "Created for VPS replace #{fixture.fetch(:vps).id} -> #{dst_vps.id}")
    expect(replace_snapshots.count).to eq(4)
    expect(replace_snapshots.where(dataset_id: fixture.fetch(:root_dataset).id).count).to eq(1)
    expect(replace_snapshots.where(dataset_id: fixture.fetch(:child_dataset).id).count).to eq(1)
    expect(replace_snapshots.where(dataset_id: dst_root.dataset_id).count).to eq(1)
    expect(replace_snapshots.where(dataset_id: dst_child.dataset_id).count).to eq(1)
    expect(replace_snapshots.pluck(:name)).to all(
      match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2} \(unconfirmed\)\z/)
    )
    expect(create_snapshot_payload.fetch('snapshots').map { |row| row.fetch('snapshot_id') }).to match_array(
      replace_snapshots.where(dataset_id: [fixture.fetch(:root_dataset).id, fixture.fetch(:child_dataset).id]).pluck(:id)
    )

    snap1_clone = Snapshot.find_by!(dataset_id: dst_root.dataset_id, name: 'snap-1')
    snap2_clone = Snapshot.find_by!(dataset_id: dst_root.dataset_id, name: 'snap-2')
    snap2_backup_sip = SnapshotInPool.find_by!(dataset_in_pool: root_backup, snapshot: snap2)
    clone_name_payload = tx_payload(chain, Transactions::Storage::CloneSnapshotName).fetch('snapshots')
    dst_replace_snapshot = replace_snapshots.find_by!(dataset_id: dst_root.dataset_id)
    src_replace_snapshot = replace_snapshots.find_by!(dataset_id: fixture.fetch(:root_dataset).id)

    expect(snap1.reload.dataset_id).to eq(fixture.fetch(:root_dataset).id)
    expect(snap2.reload.dataset_id).to eq(fixture.fetch(:root_dataset).id)
    expect(clone_name_payload.fetch(src_replace_snapshot.id.to_s)).to eq([
                                                                           dst_replace_snapshot.name,
                                                                           dst_replace_snapshot.created_at.utc.strftime('%Y-%m-%d %H:%M:%S'),
                                                                           dst_replace_snapshot.id
                                                                         ])
    expect(confirmations).to include(
      ['DatasetInPool', { 'id' => root_backup.id }, { 'dataset_id' => dst_root.dataset_id }, 'edit_after_type'],
      ['DatasetInPool', { 'id' => child_backup.id }, { 'dataset_id' => dst_child.dataset_id }, 'edit_after_type'],
      ['SnapshotInPool', { 'id' => snap1_backup_sip.id }, { 'snapshot_id' => snap1_clone.id }, 'edit_after_type'],
      ['SnapshotInPool', { 'id' => snap2_backup_sip.id }, { 'snapshot_id' => snap2_clone.id }, 'edit_after_type']
    )
    expect(confirmations).to include(
      ['DatasetAction', anything, hash_including('src_dataset_in_pool_id' => dst_root.id,
                                                 'dst_dataset_in_pool_id' => root_backup.id), 'edit_after_type']
    )
    expect(confirmations).to include(
      ['DatasetInPoolPlan', anything, hash_including('dataset_in_pool_id' => dst_root.id), 'edit_after_type']
    )
  end

  it 'marks replacement dataset create hooks when existing backup paths will be preserved' do
    fixture = create_replace_fixture(same_node: true)
    backup_pool = create_pool!(
      node: SpecSeed.other_node,
      role: :backup,
      filesystem: "spec_backup_#{SecureRandom.hex(4)}"
    )
    create_port_reservations!(node: backup_pool.node)
    attach_dataset_to_pool!(dataset: fixture.fetch(:root_dataset), pool: backup_pool)
    hook_calls = []

    with_dataset_create_hook(
      proc do |ret, dataset_in_pool, purpose: nil, source_dataset_in_pool: nil, preserve_existing_backups: false, **|
        hook_calls << {
          dataset_in_pool: dataset_in_pool,
          purpose: purpose,
          source_dataset_in_pool: source_dataset_in_pool,
          preserve_existing_backups: preserve_existing_backups
        }
        ret
      end
    ) do
      described_class.fire(
        fixture.fetch(:vps),
        fixture.fetch(:dst_node),
        start: false,
        expiration_date: nil,
        reason: 'hook context replace'
      )
    end

    root_call = hook_calls.find do |call|
      call.fetch(:source_dataset_in_pool).id == fixture.fetch(:root_dip).id
    end
    child_call = hook_calls.find do |call|
      call.fetch(:source_dataset_in_pool).id == fixture.fetch(:child_dip).id
    end

    expect(root_call).to include(
      purpose: :vps_replace,
      preserve_existing_backups: true
    )
    expect(child_call).to include(
      purpose: :vps_replace,
      preserve_existing_backups: true
    )
  end

  it 'does not mark replacement ancestors when only descendant backups will be preserved' do
    fixture = create_replace_fixture(same_node: true)
    backup_pool = create_pool!(
      node: SpecSeed.other_node,
      role: :backup,
      filesystem: "spec_backup_#{SecureRandom.hex(4)}"
    )
    create_port_reservations!(node: backup_pool.node)
    attach_dataset_to_pool!(dataset: fixture.fetch(:child_dataset), pool: backup_pool)
    hook_calls = []

    with_dataset_create_hook(
      proc do |ret, dataset_in_pool, purpose: nil, source_dataset_in_pool: nil, preserve_existing_backups: false, **|
        hook_calls << {
          dataset_in_pool: dataset_in_pool,
          purpose: purpose,
          source_dataset_in_pool: source_dataset_in_pool,
          preserve_existing_backups: preserve_existing_backups
        }
        ret
      end
    ) do
      described_class.fire(
        fixture.fetch(:vps),
        fixture.fetch(:dst_node),
        start: false,
        expiration_date: nil,
        reason: 'hook context descendant replace'
      )
    end

    root_call = hook_calls.find do |call|
      call.fetch(:source_dataset_in_pool).id == fixture.fetch(:root_dip).id
    end
    child_call = hook_calls.find do |call|
      call.fetch(:source_dataset_in_pool).id == fixture.fetch(:child_dip).id
    end

    expect(root_call).to include(
      purpose: :vps_replace,
      preserve_existing_backups: false
    )
    expect(child_call).to include(
      purpose: :vps_replace,
      preserve_existing_backups: true
    )
  end

  it 'fails when a hook creates a conflicting replacement backup dataset' do
    fixture = create_replace_fixture(same_node: true)
    backup_pool = create_pool!(
      node: SpecSeed.other_node,
      role: :backup,
      filesystem: "spec_backup_#{SecureRandom.hex(4)}"
    )
    create_port_reservations!(node: backup_pool.node)
    attach_dataset_to_pool!(dataset: fixture.fetch(:root_dataset), pool: backup_pool)

    with_dataset_create_hook(
      proc do |ret, dataset_in_pool, **|
        next ret unless dataset_in_pool.pool.role == 'hypervisor'

        backup_dip = DatasetInPool.create!(
          dataset: dataset_in_pool.dataset,
          pool: backup_pool
        )

        append(Transactions::Storage::CreateDataset, args: backup_dip) do
          create(backup_dip)
        end

        ret
      end
    ) do
      expect do
        described_class.fire(
          fixture.fetch(:vps),
          fixture.fetch(:dst_node),
          start: false,
          expiration_date: nil,
          reason: 'conflicting hook replace'
        )
      end.to raise_error(RuntimeError, /replacement backup dataset already exists/)
    end
  end

  it 'can leave existing backups on the original VPS when backup preservation is disabled' do
    fixture = create_replace_fixture(same_node: true)
    backup_pool = create_pool!(
      node: SpecSeed.other_node,
      role: :backup,
      filesystem: "spec_backup_#{SecureRandom.hex(4)}"
    )
    root_backup = attach_dataset_to_pool!(dataset: fixture.fetch(:root_dataset), pool: backup_pool)
    snap1, = create_snapshot!(dataset: fixture.fetch(:root_dataset), dip: root_backup, name: 'old-backup')
    hook_calls = []

    chain = nil
    dst_vps = nil
    with_dataset_create_hook(
      proc do |ret, dataset_in_pool, purpose: nil, source_dataset_in_pool: nil, preserve_existing_backups: false, **|
        hook_calls << {
          dataset_in_pool: dataset_in_pool,
          purpose: purpose,
          source_dataset_in_pool: source_dataset_in_pool,
          preserve_existing_backups: preserve_existing_backups
        }
        ret
      end
    ) do
      chain, dst_vps = described_class.fire(
        fixture.fetch(:vps),
        fixture.fetch(:dst_node),
        start: false,
        expiration_date: nil,
        preserve_backups: false,
        reason: 'backup preserving disabled'
      )
    end

    root_call = hook_calls.find do |call|
      call.fetch(:source_dataset_in_pool).id == fixture.fetch(:root_dip).id
    end
    confirmations = confirmations_for(chain).map do |row|
      [row.class_name, row.row_pks, row.attr_changes, row.confirm_type]
    end

    expect(tx_classes(chain)).not_to include(
      Transactions::Storage::CreateSnapshots,
      Transactions::Storage::RenameDataset,
      Transactions::Storage::LocalSend
    )
    expect(root_backup.reload.dataset_id).to eq(fixture.fetch(:root_dataset).id)
    expect(snap1.reload.dataset_id).to eq(fixture.fetch(:root_dataset).id)
    expect(confirmations).not_to include(
      ['DatasetInPool', { 'id' => root_backup.id }, { 'dataset_id' => dst_vps.dataset_in_pool.dataset_id },
       'edit_after_type'],
      ['Snapshot', { 'id' => snap1.id }, { 'dataset_id' => dst_vps.dataset_in_pool.dataset_id }, 'edit_after_type']
    )
    expect(root_call).to include(
      purpose: :vps_replace,
      preserve_existing_backups: false
    )
  end

  it 'can move existing backups without creating replace-time backup snapshots' do
    fixture = create_replace_fixture(same_node: true)
    backup_pool = create_pool!(
      node: SpecSeed.other_node,
      role: :backup,
      filesystem: "spec_backup_#{SecureRandom.hex(4)}"
    )
    root_backup = attach_dataset_to_pool!(dataset: fixture.fetch(:root_dataset), pool: backup_pool)
    snap1, = create_snapshot!(dataset: fixture.fetch(:root_dataset), dip: root_backup, name: 'backup-only')

    chain, dst_vps = described_class.fire(
      fixture.fetch(:vps),
      fixture.fetch(:dst_node),
      start: false,
      expiration_date: nil,
      preserve_backup_history: false,
      reason: 'backup moving replace'
    )
    confirmations = confirmations_for(chain).map do |row|
      [row.class_name, row.row_pks, row.attr_changes, row.confirm_type]
    end

    expect(tx_classes(chain)).not_to include(Transactions::Storage::CreateSnapshots)
    expect(tx_classes(chain)).to include(Transactions::Storage::RenameDataset)
    expect(Snapshot.where(label: "Created for VPS replace #{fixture.fetch(:vps).id} -> #{dst_vps.id}")).to be_empty
    expect(confirmations).to include(
      ['DatasetInPool', { 'id' => root_backup.id }, { 'dataset_id' => dst_vps.dataset_in_pool.dataset_id },
       'edit_after_type'],
      ['Snapshot', { 'id' => snap1.id }, { 'dataset_id' => dst_vps.dataset_in_pool.dataset_id }, 'edit_after_type']
    )
  end
end
