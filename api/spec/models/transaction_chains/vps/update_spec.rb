# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::Vps::Update do
  around do |example|
    unlock_transaction_signer!
    with_current_context(user: user) { example.run }
  end

  let(:user) { SpecSeed.user }

  before do
    allow(MailTemplate).to receive(:send_mail!).and_return(nil)
  end

  def create_update_vps_fixture
    pool = create_pool!(node: SpecSeed.node, role: :hypervisor)
    dataset, dip = create_dataset_with_pool!(
      user: user,
      pool: pool,
      name: "update-root-#{SecureRandom.hex(4)}"
    )

    ensure_numeric_resources!(user: user, environment: SpecSeed.node.location.environment)
    allocate_dip_diskspace!(dip, user: user, value: 10_240)

    vps = create_vps_for_dataset!(
      user: user,
      node: SpecSeed.node,
      dataset_in_pool: dip,
      dns_resolver: SpecSeed.dns_resolver
    )
    allocate_vps_resources!(vps, user: user, cpu: 2, memory: 2048, swap: 0)
    seed_vps_features!(vps)
    create_network_interface!(vps, name: 'eth0')
    NodeCurrentStatus.find_or_create_by!(node: SpecSeed.node) do |status|
      status.vpsadmin_version = 'spec'
      status.kernel = 'spec'
      status.update_count = 1
      status.cgroup_version = :cgroup_v2
      status.pool_state = :online
      status.pool_scan = :none
      status.pool_checked_at = Time.now.utc
      status.created_at = Time.now.utc
      status.updated_at = Time.now.utc
    end

    [dataset, vps]
  end

  it 'queues hostname and DNS resolver updates' do
    _dataset, vps = create_update_vps_fixture
    original_hostname = vps.hostname

    chain, updated_vps = described_class.fire(vps, {
      hostname: 'new-update-host',
      dns_resolver_id: SpecSeed.other_dns_resolver.id
    })

    expect(updated_vps).to eq(vps)
    expect(tx_classes(chain)).to include(
      Transactions::Vps::Hostname,
      Transactions::Vps::DnsResolver
    )
    expect(tx_payload(chain, Transactions::Vps::Hostname)).to include(
      'hostname' => 'new-update-host',
      'original' => original_hostname
    )
    expect(tx_payload(chain, Transactions::Vps::DnsResolver)).to include(
      'nameserver' => ['192.0.2.54'],
      'original' => ['192.0.2.53']
    )
  end

  it 'queues unmanage transactions when hostname and DNS resolver management are disabled' do
    _dataset, vps = create_update_vps_fixture

    chain, = described_class.fire(vps, {
      manage_hostname: false,
      dns_resolver_id: nil
    })

    expect(tx_classes(chain)).to include(
      Transactions::Vps::UnmanageHostname,
      Transactions::Vps::UnmanageDnsResolver
    )
  end

  it 'queues resources and logs the change when resources are updated' do
    _dataset, vps = create_update_vps_fixture

    chain, = described_class.fire(vps, {
      memory: 4096,
      cpu: 3,
      swap: 256,
      change_reason: 'scale up'
    })
    payload = tx_payload(chain, Transactions::Vps::Resources)

    expect(tx_classes(chain)).to include(Transactions::Vps::Resources)
    expect(payload.fetch('resources')).to include(
      include('resource' => 'cpu', 'value' => 3, 'original' => 2),
      include('resource' => 'memory', 'value' => 4096, 'original' => 2048),
      include('resource' => 'swap', 'value' => 256, 'original' => 0)
    )
    expect(ObjectHistory.where(tracked_object: vps, event_type: 'resources').count).to eq(1)
    expect(MailTemplate).to have_received(:send_mail!)
  end

  it 'queues Autostart only when autostart is enabled' do
    _dataset, vps = create_update_vps_fixture
    vps.update!(autostart_enable: true, autostart_priority: 1000)

    chain, = described_class.fire(vps, { autostart_priority: 200 })

    expect(tx_classes(chain)).to include(Transactions::Vps::Autostart)
    expect(tx_payload(chain, Transactions::Vps::Autostart)).to include(
      'new' => include('enable' => true, 'priority' => 200),
      'original' => include('enable' => true, 'priority' => 1000)
    )
  end

  it 'queues Chown when the user namespace map changes' do
    _dataset, vps = create_update_vps_fixture
    other_map = create_user_namespace_map!(user: user)
    original_map_id = vps.user_namespace_map_id

    chain, = described_class.fire(vps, { user_namespace_map_id: other_map.id })

    expect(tx_classes(chain)).to include(
      Transactions::UserNamespace::UseMap,
      Transactions::Vps::Chown,
      Transactions::UserNamespace::DisuseMap
    )
    expect(tx_payload(chain, Transactions::Vps::Chown)).to include(
      'original_userns_map' => original_map_id.to_s,
      'new_userns_map' => other_map.id.to_s
    )
  end

  it 'delegates enable_network changes and map mode changes to the expected transactions' do
    _dataset, vps = create_update_vps_fixture

    chain, = described_class.fire(vps, {
      enable_network: false,
      map_mode: 'zfs'
    })

    expect(tx_classes(chain)).to include(
      Transactions::NetworkInterface::Disable,
      Transactions::Vps::MapMode
    )
    expect(tx_payload(chain, Transactions::Vps::MapMode)).to include(
      'new_map_mode' => 'zfs',
      'original_map_mode' => 'native'
    )
  end

  it 'persists DB-only changes immediately when the chain stays empty' do
    _dataset, vps = create_update_vps_fixture
    original_priority = vps.autostart_priority

    chain, updated_vps = described_class.fire(vps, {
      info: 'db-only update',
      autostart_priority: original_priority + 50
    })

    expect(chain).to be_nil
    expect(updated_vps.reload.info).to eq('db-only update')
    expect(updated_vps.autostart_priority).to eq(original_priority + 50)
  end
end
