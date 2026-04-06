# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::Vps::Clone::OsToOs do
  around do |example|
    with_current_context { example.run }
  end

  let(:user) { SpecSeed.user }

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

  def reallocate_dip_diskspace!(dip, user:, value:)
    with_current_context do
      dip.reallocate_resource!(
        :diskspace,
        value,
        user: user,
        save: true,
        override: true
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

  def ensure_user_namespace_entries!(userns_map)
    return if userns_map.user_namespace_map_entries.exists?

    %i[uid gid].each do |kind|
      UserNamespaceMapEntry.create!(
        user_namespace_map: userns_map,
        kind: kind,
        vps_id: 0,
        ns_id: 0,
        count: userns_map.user_namespace.size
      )
    end
  end

  def create_location_network!(location:, address:, prefix:, split_prefix:, role:, ip_version:)
    network = Network.create!(
      address: address,
      prefix: prefix,
      split_prefix: split_prefix,
      role: role,
      purpose: :vps,
      managed: true,
      split_access: :no_access,
      primary_location: location,
      ip_version: ip_version,
      label: "spec-net-#{SecureRandom.hex(4)}"
    )

    LocationNetwork.create!(
      location: location,
      network: network,
      primary: true,
      priority: 10,
      autopick: true,
      userpick: true
    )

    network
  end

  def ensure_backup_hook_environments!
    {
      'Production' => 'production.test',
      'Playground' => 'playground.test',
      'Staging' => 'staging.test'
    }.each do |label, domain|
      Environment.find_or_create_by!(label: label) do |env|
        env.domain = domain
        env.user_ip_ownership = false
      end
    end
  end

  def with_backup_dataset_create_hook(backup_pool)
    create_hooks = HaveAPI::Hooks.hooks.fetch(DatasetInPool).fetch(:create)
    original_listeners = create_hooks.fetch(:listeners)

    create_hooks[:listeners] = [
      proc do |ret, dataset_in_pool|
        next ret unless dataset_in_pool.pool.role == 'hypervisor'

        dataset_in_pool.update!(
          min_snapshots: 1,
          max_snapshots: 1
        )

        begin
          backup_dip = DatasetInPool.create!(
            dataset: dataset_in_pool.dataset,
            pool: backup_pool
          )

          append(Transactions::Storage::CreateDataset, args: backup_dip) do
            create(backup_dip)
          end
        rescue ActiveRecord::RecordNotUnique
          nil
        end

        ret
      end
    ]

    yield
  ensure
    create_hooks[:listeners] = original_listeners
  end

  def create_network_interface!(vps, name:, kind: :veth_routed, max_tx: 0, max_rx: 0)
    NetworkInterface.create!(
      vps: vps,
      kind: kind,
      name: name,
      max_tx: max_tx,
      max_rx: max_rx
    )
  end

  def create_mount!(vps:, dataset_in_pool:, dst:, snapshot_in_pool: nil)
    Mount.create!(
      vps: vps,
      dataset_in_pool: dataset_in_pool,
      snapshot_in_pool: snapshot_in_pool,
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

  def tx_payload(chain, klass, nth: 0)
    tx = transactions_for(chain).select { |row| Transaction.for_type(row.handle) == klass }.fetch(nth)
    JSON.parse(tx.input).fetch('input')
  end

  def confirmation_attr_changes(chain, class_name, confirm_type: nil)
    confirmations_for(chain).select do |row|
      row.class_name == class_name && (confirm_type.nil? || row.confirm_type == confirm_type.to_s)
    end.map(&:attr_changes)
  end

  def create_clone_fixture(user: SpecSeed.user, same_location: true, same_node: false)
    src_node = SpecSeed.node
    dst_location = same_location ? src_node.location : SpecSeed.other_location
    dst_node =
      if same_node
        src_node
      else
        create_node!(
          location: dst_location,
          role: :node,
          name: "clone-dst-#{SecureRandom.hex(3)}"
        )
      end
    src_pool = create_pool!(node: src_node, role: :hypervisor)
    src_pool.update!(migration_public_key: 'spec-src-pubkey')
    dst_pool = create_pool!(
      node: dst_node,
      role: :hypervisor,
      filesystem: "spec_hv_dst_#{SecureRandom.hex(4)}"
    )
    root_dataset, root_dip = create_dataset_with_pool!(
      user: user,
      pool: src_pool,
      name: "clone-root-#{SecureRandom.hex(4)}"
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
    ensure_user_namespace_entries!(vps.user_namespace_map)
    allocate_vps_resources!(vps, user: user)
    seed_vps_features!(vps)

    {
      src_node: src_node,
      dst_node: dst_node,
      src_pool: src_pool,
      dst_pool: dst_pool,
      root_dataset: root_dataset,
      root_dip: root_dip,
      child_dataset: child_dataset,
      child_dip: child_dip,
      vps: vps
    }
  end

  it 'uses local copy for same-node clones and skips remote send steps' do
    fixture = create_clone_fixture(same_node: true)
    vps = fixture.fetch(:vps)
    attrs = {
      user: vps.user,
      hostname: 'same-node-clone',
      stop: false,
      dataset_plans: false,
      resources: true,
      features: true
    }

    chain, dst_vps = described_class.fire(vps, fixture.fetch(:dst_node), attrs)
    classes = tx_classes(chain)
    payload = tx_payload(chain, Transactions::Vps::Copy)

    expect(classes).to include(
      Transactions::Queue::Reserve,
      Transactions::Vps::Copy,
      Transactions::Queue::Release,
      Transactions::Vps::Features
    )
    expect(classes).not_to include(
      Transactions::Pool::AuthorizeSendKey,
      Transactions::Vps::SendConfig,
      Transactions::Vps::SendRootfs,
      Transactions::Vps::SendState,
      Transactions::Vps::SendCleanup
    )
    expect(classes.count(Transactions::Queue::Reserve)).to eq(2)
    expect(classes.count(Transactions::Queue::Release)).to eq(2)
    expect(payload.fetch('consistent')).to be(false)
    expect(payload.fetch('network_interfaces')).to be(false)
    expect(payload.fetch('as_dataset')).to eq(
      File.join(fixture.fetch(:dst_pool).filesystem, dst_vps.dataset_in_pool.dataset.full_name)
    )
  end

  it 'uses send transactions for remote clones and pins SendConfig payload' do
    fixture = create_clone_fixture
    vps = fixture.fetch(:vps)
    attrs = {
      user: vps.user,
      hostname: 'remote-clone',
      stop: false,
      dataset_plans: false,
      resources: true,
      features: false
    }

    chain, dst_vps = described_class.fire(vps, fixture.fetch(:dst_node), attrs)
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
    expect(classes.count(Transactions::Queue::Reserve)).to eq(2)
    expect(classes.count(Transactions::Queue::Release)).to eq(2)
    expect(payload.fetch('as_id')).to eq(dst_vps.id.to_s)
    expect(payload.fetch('network_interfaces')).to be(false)
    expect(payload.fetch('snapshots')).to be(false)
  end

  it 'adds stop, sync, and source restart for consistent remote clones of running VPSes' do
    fixture = create_clone_fixture
    vps = fixture.fetch(:vps)
    set_vps_running!(vps)

    chain, dst_vps = described_class.fire(
      vps,
      fixture.fetch(:dst_node),
      user: vps.user,
      hostname: 'consistent-remote-clone',
      stop: true,
      dataset_plans: false,
      resources: true,
      features: false
    )
    classes = tx_classes(chain)
    start_vps_ids = transactions_for(chain).select do |tx|
      Transaction.for_type(tx.handle) == Transactions::Vps::Start
    end.map(&:vps_id)

    expect(classes).to include(
      Transactions::Vps::Stop,
      Transactions::Vps::SendSync,
      Transactions::Vps::SendState
    )
    expect(start_vps_ids).to include(vps.id, dst_vps.id)
  end

  it 'uses both user namespace maps and chowns when cloning to another owner' do
    fixture = create_clone_fixture
    vps = fixture.fetch(:vps)
    dst_user = SpecSeed.other_user
    dst_map = create_user_namespace_map!(user: dst_user)
    ensure_user_namespace_entries!(dst_map)
    ensure_numeric_resources!(
      user: dst_user,
      environment: fixture.fetch(:dst_node).location.environment
    )

    chain, dst_vps = described_class.fire(
      vps,
      fixture.fetch(:dst_node),
      user: dst_user,
      hostname: 'different-owner-clone',
      stop: false,
      dataset_plans: false,
      resources: true,
      features: false
    )
    use_map_payloads = transactions_for(chain).select do |tx|
      Transaction.for_type(tx.handle) == Transactions::UserNamespace::UseMap
    end.map { |tx| JSON.parse(tx.input).fetch('input') }

    expect(tx_classes(chain)).to include(
      Transactions::UserNamespace::UseMap,
      Transactions::Vps::Chown,
      Transactions::UserNamespace::DisuseMap
    )
    expect(use_map_payloads.map { |payload| payload.fetch('name') }).to eq(
      [vps.user_namespace_map.id.to_s, dst_map.id.to_s]
    )
    expect(dst_vps.user_id).to eq(dst_user.id)
    expect(dst_vps.user_namespace_map_id).to eq(dst_map.id)
  end

  it 'emits hostname changes and keeps universal resolvers untouched' do
    fixture = create_clone_fixture
    vps = fixture.fetch(:vps)
    vps.update!(manage_hostname: true, dns_resolver: SpecSeed.dns_resolver)

    chain, dst_vps = described_class.fire(
      vps,
      fixture.fetch(:dst_node),
      user: vps.user,
      hostname: 'renamed-clone',
      stop: false,
      dataset_plans: false,
      resources: true,
      features: false
    )

    expect(tx_classes(chain)).to include(Transactions::Vps::Hostname, Transactions::Vps::DnsResolver)
    expect(dst_vps.dns_resolver_id).to eq(vps.dns_resolver_id)
  end

  it 'picks a resolver in the destination location for location-specific DNS' do
    fixture = create_clone_fixture(same_location: false)
    vps = fixture.fetch(:vps)
    dst_resolver = DnsResolver.create!(
      addrs: '192.0.2.201',
      label: "dst-dns-#{SecureRandom.hex(3)}",
      is_universal: false,
      location: fixture.fetch(:dst_node).location,
      ip_version: 4
    )
    vps.update!(
      manage_hostname: true,
      dns_resolver: SpecSeed.other_dns_resolver
    )

    chain, dst_vps = described_class.fire(
      vps,
      fixture.fetch(:dst_node),
      user: vps.user,
      hostname: 'cross-location-clone',
      stop: false,
      dataset_plans: false,
      resources: true,
      features: false
    )

    expect(tx_classes(chain)).to include(Transactions::Vps::Hostname, Transactions::Vps::DnsResolver)
    expect(dst_vps.dns_resolver_id).to eq(dst_resolver.id)
  end

  it 'copies dataset plans and dataset expansion histories when requested' do
    fixture = create_clone_fixture
    vps = fixture.fetch(:vps)
    backup_pool = create_pool!(
      node: create_node!(location: fixture.fetch(:src_node).location, role: :storage),
      role: :backup
    )
    attach_dataset_to_pool!(dataset: fixture.fetch(:root_dataset), pool: backup_pool)
    create_daily_backup_env_plan!(environment: fixture.fetch(:src_node).location.environment, user_add: true)
    VpsAdmin::API::DatasetPlans.plans[:daily_backup].register(fixture.fetch(:root_dip))

    expansion = DatasetExpansion.create_for_expanded!(
      fixture.fetch(:root_dip),
      vps: vps,
      dataset: fixture.fetch(:root_dataset),
      state: :active,
      original_refquota: 10_240,
      added_space: 2_048,
      enable_notifications: false,
      max_over_refquota_seconds: 3_600
    )
    expansion.dataset_expansion_histories.create!(
      added_space: 1_024,
      original_refquota: 12_288,
      new_refquota: 13_312,
      admin: SpecSeed.admin
    )

    chain = nil
    dst_vps = nil

    with_backup_dataset_create_hook(backup_pool) do
      chain, dst_vps = described_class.fire(
        vps,
        fixture.fetch(:dst_node),
        user: vps.user,
        hostname: 'planned-clone',
        stop: false,
        dataset_plans: true,
        resources: true,
        features: false
      )
    end

    dst_expansion = DatasetExpansion.find_by!(vps: dst_vps, dataset: dst_vps.dataset)
    dataset_expansion_changes = confirmation_attr_changes(
      chain,
      'Dataset',
      confirm_type: :edit_after_type
    ).select { |changes| changes.has_key?('dataset_expansion_id') || changes.has_key?(:dataset_expansion_id) }

    expect(dst_vps.dataset_in_pool.dataset_in_pool_plans.count).to eq(1)
    expect(dst_expansion).not_to be_nil
    expect(dst_expansion.added_space).to eq(expansion.added_space)
    expect(dst_expansion.dataset_expansion_histories.count).to eq(2)
    expect(dataset_expansion_changes).to include(include('dataset_expansion_id' => dst_expansion.id))
  end

  it 'does not register dataset plans when dataset_plans is false' do
    fixture = create_clone_fixture
    vps = fixture.fetch(:vps)
    ensure_backup_hook_environments!
    backup_pool = create_pool!(
      node: create_node!(location: fixture.fetch(:src_node).location, role: :storage),
      role: :backup
    )
    attach_dataset_to_pool!(dataset: fixture.fetch(:root_dataset), pool: backup_pool)
    create_daily_backup_env_plan!(environment: fixture.fetch(:src_node).location.environment, user_add: true)
    VpsAdmin::API::DatasetPlans.plans[:daily_backup].register(fixture.fetch(:root_dip))

    _chain, dst_vps = described_class.fire(
      vps,
      fixture.fetch(:dst_node),
      user: vps.user,
      hostname: 'no-plan-clone',
      stop: false,
      dataset_plans: false,
      resources: true,
      features: false
    )

    expect(dst_vps.dataset_in_pool.dataset_in_pool_plans).to be_empty
  end

  it 'clones descendant mounts, skips snapshot mounts, and ignores external mounts' do
    fixture = create_clone_fixture
    vps = fixture.fetch(:vps)
    external_dataset, external_dip = create_dataset_with_pool!(
      user: vps.user,
      pool: fixture.fetch(:src_pool),
      name: "external-#{SecureRandom.hex(4)}"
    )
    allocate_dip_diskspace!(external_dip, user: vps.user, value: 10_240)
    _snapshot, sip = create_snapshot!(
      dataset: fixture.fetch(:root_dataset),
      dip: fixture.fetch(:root_dip),
      name: 'clone-snap'
    )

    mount_chain, = TransactionChains::Vps::MountDataset.fire(
      vps,
      fixture.fetch(:child_dataset),
      '/mnt/sub',
      mode: 'rw',
      enabled: true
    )
    mount_chain.release_locks
    create_mount!(vps: vps, dataset_in_pool: fixture.fetch(:root_dip), snapshot_in_pool: sip, dst: '/mnt/snapshot')
    create_mount!(vps: vps, dataset_in_pool: external_dip, dst: '/mnt/external')

    _chain, dst_vps = described_class.fire(
      vps,
      fixture.fetch(:dst_node),
      user: vps.user,
      hostname: 'mount-clone',
      stop: false,
      dataset_plans: false,
      resources: true,
      features: false
    )
    dst_mounts = dst_vps.mounts.order(:dst).to_a
    dst_child = dst_vps.datasets.find_by!(name: fixture.fetch(:child_dataset).name)
    dst_child_dip = DatasetInPool.find_by!(dataset: dst_child, pool: dst_vps.dataset_in_pool.pool)

    expect(dst_mounts.map(&:dst)).to include('/mnt/sub')
    expect(dst_mounts.map(&:dst)).not_to include('/mnt/snapshot', '/mnt/external')
    expect(dst_mounts.find { |mnt| mnt.dst == '/mnt/sub' }.dataset_in_pool_id).to eq(dst_child_dip.id)
    expect(external_dataset).to be_persisted
  end

  it 'keeps descendant diskspace allocations below the minimum when cloning' do
    fixture = create_clone_fixture
    vps = fixture.fetch(:vps)
    reallocate_dip_diskspace!(fixture.fetch(:child_dip), user: vps.user, value: 128)

    _chain, dst_vps = described_class.fire(
      vps,
      fixture.fetch(:dst_node),
      user: vps.user,
      hostname: 'small-descendant-clone',
      stop: false,
      dataset_plans: false,
      resources: true,
      features: false
    )
    dst_child = dst_vps.datasets.find_by!(name: fixture.fetch(:child_dataset).name)
    dst_child_dip = DatasetInPool.find_by!(dataset: dst_child, pool: dst_vps.dataset_in_pool.pool)
    dst_child_diskspace_use = dst_child_dip.get_cluster_resources([:diskspace]).take!

    expect(fixture.fetch(:child_dip).reload.diskspace).to eq(128)
    expect(dst_child_diskspace_use.value).to eq(128)
  end

  it 'clones interfaces, reallocates all IP resource buckets, and forwards address_location to allocation' do
    fixture = create_clone_fixture
    vps = fixture.fetch(:vps)
    dst_location = fixture.fetch(:dst_node).location
    private_network = create_location_network!(
      location: dst_location,
      address: '198.18.0.0',
      prefix: 24,
      split_prefix: 32,
      role: :private_access,
      ip_version: 4
    )
    v6_network = create_location_network!(
      location: dst_location,
      address: '2001:db8:1::',
      prefix: 64,
      split_prefix: 128,
      role: :public_access,
      ip_version: 6
    )
    netif = create_network_interface!(vps, name: 'eth0')
    create_ip_address!(
      network: SpecSeed.network_v4,
      location: dst_location,
      network_interface: netif,
      addr: "192.0.2.#{20 + SecureRandom.random_number(20)}"
    )
    create_ip_address!(
      network: private_network,
      location: dst_location,
      network_interface: netif,
      addr: "198.18.0.#{20 + SecureRandom.random_number(20)}"
    )
    create_ip_address!(
      network: v6_network,
      location: dst_location,
      network_interface: netif,
      addr: "2001:db8:1::#{20 + SecureRandom.random_number(20)}"
    )

    create_ip_address!(
      network: SpecSeed.network_v4,
      location: dst_location,
      addr: "192.0.2.#{120 + SecureRandom.random_number(20)}"
    )
    create_ip_address!(
      network: private_network,
      location: dst_location,
      addr: "198.18.0.#{120 + SecureRandom.random_number(20)}"
    )
    create_ip_address!(
      network: v6_network,
      location: dst_location,
      addr: "2001:db8:1::#{120 + SecureRandom.random_number(20)}"
    )

    seen_address_locations = []
    allow(TransactionChains::Ip::Allocate).to receive(:use_in).and_wrap_original do |original, root_chain, opts|
      seen_address_locations << opts.fetch(:kwargs).fetch(:address_location)
      forwarded = opts.dup
      forwarded[:kwargs] = opts.fetch(:kwargs).dup
      forwarded[:kwargs][:address_location] = nil
      original.call(root_chain, forwarded)
    end

    chain, dst_vps = described_class.fire(
      vps,
      fixture.fetch(:dst_node),
      user: vps.user,
      hostname: 'network-clone',
      stop: false,
      dataset_plans: false,
      resources: true,
      features: false,
      address_location: SpecSeed.other_location
    )
    resource_edits = confirmation_attr_changes(
      chain,
      'ClusterResourceUse',
      confirm_type: :edit_after_type
    ).select { |changes| changes.has_key?('value') || changes.has_key?(:value) }

    expect(tx_classes(chain)).to include(
      Transactions::NetworkInterface::CreateVethRouted,
      Transactions::NetworkInterface::AddRoute
    )
    expect(dst_vps.network_interfaces.count).to eq(1)
    expect(seen_address_locations).to all(eq(SpecSeed.other_location))
    expect(resource_edits.count).to be >= 3
  end

  it 'keeps subdatasets=false as a pending contract until descendant selection is wired' do
    pending(
      'subdatasets=false should skip descendant dataset serialization and subdataset mounts, ' \
      'but TransactionChains::Vps::Clone::OsToOs always serializes descendants'
    )

    fixture = create_clone_fixture
    vps = fixture.fetch(:vps)

    _chain, dst_vps = described_class.fire(
      vps,
      fixture.fetch(:dst_node),
      user: vps.user,
      hostname: 'subdatasets-pending',
      stop: false,
      dataset_plans: false,
      resources: true,
      features: false,
      subdatasets: false
    )

    expect(dst_vps.datasets.where(name: fixture.fetch(:child_dataset).name)).to be_empty
  end

  it 'keeps keep_snapshots=true as a pending contract until remote snapshot retention is wired' do
    pending(
      'keep_snapshots=true should preserve temporary snapshots created for remote consistent clones, ' \
      'but TransactionChains::Vps::Clone::OsToOs does not consult the flag'
    )

    fixture = create_clone_fixture
    vps = fixture.fetch(:vps)
    set_vps_running!(vps)

    chain, = described_class.fire(
      vps,
      fixture.fetch(:dst_node),
      user: vps.user,
      hostname: 'keep-snapshots-pending',
      stop: true,
      dataset_plans: false,
      resources: true,
      features: false,
      keep_snapshots: true
    )

    expect(tx_classes(chain)).not_to include(Transactions::Vps::SendCleanup)
  end
end
