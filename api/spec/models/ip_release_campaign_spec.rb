require 'spec_helper'

RSpec.describe IpReleaseCampaign do
  around do |example|
    with_current_context { example.run }
  end

  before do
    unlock_transaction_signer!
    ensure_available_node_status!(SpecSeed.node)
  end

  def expect_staged(c, ips)
    attempt = c.latest_release_attempt
    expect(attempt.state).to eq('running'), attempt.error
    expect(attempt.ip_release_request_addresses.pluck(:ip_address_id)).to match_array(ips.map(&:id))
    changes = confirmations_for(attempt.transaction_chain)
    ips.each do |ip|
      expect(ip.reload.user_id).not_to be_nil
      edit = changes.find { |row| row.class_name == 'IpAddress' && row.row_pks == { 'id' => ip.id } }
      expect(edit.confirm_type).to eq('edit_after_type')
      expect(edit.attr_changes.symbolize_keys).to include(user_id: nil, charged_environment_id: nil)
    end
  end

  def address(user: SpecSeed.user)
    create_ip_address!(user:)
  end

  def campaign(ips, **attrs)
    described_class.create_selected!(ids: ips.map(&:id), actor: SpecSeed.admin,
                                     deadline: Time.now + 604_800,
                                     **attrs)
  end

  def item(c)
    c.ip_release_request_addresses.first
  end

  def ip_counts(c)
    c.load_ip_counts
    [c.total_ip_count, c.to_release_ip_count, c.kept_ip_count]
  end

  it 'counts current protection, refreshes after policy edits and retains historical totals' do
    ips = Array.new(7) { address }
    c = campaign(ips)
    rows = c.ip_release_request_addresses.order(:id).to_a
    expect(ip_counts(c)).to eq([7, 7, 0])
    rows[0].ip_release_request.keep!(ids: [rows[0].id], reason: 'Migration', actor: SpecSeed.user)
    rows[1].exempt!(reason: 'Reservation', actor: SpecSeed.admin)
    fixture = create_netif_vps_fixture!(user: SpecSeed.user)
    ips[2].update!(network_interface: fixture[:netif])
    export, = create_export_for_dataset!(dataset_in_pool: fixture[:dataset_in_pool])
    ExportHost.create!(export:, ip_address: ips[3], rw: true, sync: true,
                       subtree_check: false, root_squash: false)
    ips[4].update!(user: SpecSeed.other_user)
    rows[5].update!(released_at: Time.now)
    expect(ip_counts(c)).to eq([7, 1, 4])
    c.edit!({ allow_keep: false }, actor: SpecSeed.admin)
    expect(ip_counts(c)).to eq([7, 2, 3])
    c.edit!({ allow_keep: true }, actor: SpecSeed.admin)
    expect(ip_counts(c)).to eq([7, 1, 4])
    c.close!(actor: SpecSeed.admin)
    expect(ip_counts(c)).to eq([7, 0, 4])
  end

  it 'counts host assignments and routing dependencies as kept allocations' do
    ips = [address, address]
    c = campaign(ips)
    ips[0].host_ip_addresses.first.update!(order: 0)
    address.update!(route_via: ips[1].host_ip_addresses.first)
    expect(ip_counts(c)).to eq([2, 0, 2])
  end

  it 'counts missing allocations and unavailable owners only in the total' do
    ips = [address, address(user: SpecSeed.other_user)]
    c = campaign(ips)
    ips[0].destroy!
    SpecSeed.other_user.update!(object_state: :soft_delete)
    expect(ip_counts(c)).to eq([2, 0, 0])
  end

  it 'counts each IPv6 allocation once regardless of its size' do
    SpecSeed.network_v6.update!(split_prefix: 80)
    ip = create_ip_address!(network: SpecSeed.network_v6, user: SpecSeed.user,
                            addr: '2001:db8::', prefix: 80, size: 256)
    c = campaign([ip])
    allow(c).to receive(:load_ip_counts).and_call_original
    expect([c.total_ip_count, c.to_release_ip_count, c.kept_ip_count]).to eq([1, 1, 0])
    expect(c).to have_received(:load_ip_counts).once
  end

  it 'includes pending releases after closure but only totals completed releases' do
    ensure_available_node_status!(SpecSeed.node)
    ip = address
    ip.host_ip_addresses.first.update!(user_created: true)
    c = campaign([ip])
    c.release!(actor: SpecSeed.admin)
    expect(item(c).protection).to eq('releasing')
    expect(ip_counts(c)).to eq([1, 1, 0])
    c.close!(actor: SpecSeed.admin)
    expect(ip_counts(c)).to eq([1, 1, 0])
    item(c).update!(released_at: Time.now)
    expect(ip_counts(c)).to eq([1, 0, 0])
  end

  it 'counts failed cleanup as eligible for another attempt while the campaign is open' do
    ensure_available_node_status!(SpecSeed.node)
    ip = address
    ip.host_ip_addresses.first.update!(user_created: true)
    c = campaign([ip])
    c.release!(actor: SpecSeed.admin)
    item(c).release_chain.update!(state: :failed)
    expect(item(c).last_result).to eq('failed')
    expect(ip_counts(c)).to eq([1, 1, 0])
    c.close!(actor: SpecSeed.admin)
    expect(ip_counts(c)).to eq([1, 0, 0])
  end

  it 'sets and removes exemptions across owners without changing user reasons' do
    c = campaign([address, address(user: SpecSeed.other_user)])
    items = c.ip_release_request_addresses.order(:id).to_a
    items.first.ip_release_request.keep!(ids: [items.first.id], reason: 'Member reservation', actor: SpecSeed.user)
    c.exempt!(ids: items.map(&:id), reason: ' Approved reservation ', actor: SpecSeed.admin)
    expect(items.map { |entry| entry.reload.exemption_reason }).to eq(['Approved reservation'] * 2)
    expect(items.map(&:exempted_by_id)).to eq([SpecSeed.admin.id] * 2)
    expect(items.map(&:exempted_at).uniq.length).to eq(1)
    c.exempt!(ids: items.map(&:id), reason: nil, actor: SpecSeed.admin)
    expect(items.map { |entry| entry.reload.exempted_by_id }).to eq([nil, nil])
    expect(items.first.keep_reason).to eq('Member reservation')
    expect(items.first.kept_by_id).to eq(SpecSeed.user.id)
  end

  it 'rejects a whole exemption batch when any allocation changed or belongs to another campaign' do
    ips = [address, address]
    c = campaign(ips)
    ids = c.ip_release_request_addresses.order(:id).pluck(:id)
    foreign = item(campaign([address]))
    [[], [ids.first, foreign.id], [ids.first, 2_000_000_000], (1..101).to_a].each do |selection|
      expect { c.exempt!(ids: selection, reason: 'Keep', actor: SpecSeed.admin) }.to raise_error(described_class::Error)
      expect(item(c).reload.exempted_at).to be_nil
    end
    ips.last.update!(user: SpecSeed.other_user)
    expect { c.exempt!(ids:, reason: 'Keep', actor: SpecSeed.admin) }.to raise_error(described_class::Error, 'owner_changed')
    expect(c.ip_release_request_addresses.where.not(exempted_at: nil)).to be_empty
  end

  it 'rolls back invalid reasons and rejects released or closed selections' do
    c = campaign([address, address])
    ids = c.ip_release_request_addresses.pluck(:id)
    ['', ' ', 'x' * 2001].each do |reason|
      expect { c.exempt!(ids:, reason:, actor: SpecSeed.admin) }.to raise_error(ActiveRecord::RecordInvalid)
      expect(c.ip_release_request_addresses.where.not(exempted_at: nil)).to be_empty
    end
    c.ip_release_request_addresses.last.update!(released_at: Time.now)
    expect { c.exempt!(ids:, reason: 'Keep', actor: SpecSeed.admin) }.to raise_error(described_class::Error, 'already_released')
    c.close!(actor: SpecSeed.admin)
    expect { c.exempt!(ids: [ids.first], reason: 'Keep', actor: SpecSeed.admin) }.to raise_error(described_class::Error, 'closed')
    expect(item(c).reload.exempted_at).to be_nil
  end

  it 'snapshots exact allocations and prevents overlapping campaigns' do
    ip = address
    c = campaign([ip])
    expect(item(c).attributes).to include('address' => ip.addr, 'prefix' => ip.prefix)
    expect { campaign([ip]) }.to raise_error(described_class::Error, 'duplicate_addresses')
    expect(described_class.count).to eq(1)
  end

  it 'rejects unowned, assigned and malformed selections atomically' do
    ip = address
    free_ip = address(user: nil)
    expect { campaign([ip, free_ip]) }.to raise_error(described_class::Error)
    expect(described_class.count).to eq(0)
    expect { described_class.address_ids!(['1']) }.to raise_error(described_class::Error)
  end

  it 'reports legacy missing accounting provenance without changing ownership or quota' do
    ip = address
    ip.update!(charged_environment: nil)
    config = SpecSeed.user.environment_user_configs.find_by!(environment: SpecSeed.environment)
    usage = config.ipv4
    c = campaign([ip])
    c.release!(actor: SpecSeed.admin)
    expect(c.latest_release_attempt.state).to eq('preparation_failed')
    expect(c.latest_release_attempt.error).to include('reconcile its accounting')
    expect(ip.reload.user_id).to eq(SpecSeed.user.id)
    expect(config.reload.ipv4).to eq(usage)
  end

  it 'releases a full campaign populated by managed network additions exactly once' do
    network = SpecSeed.network_v4.dup
    network.update!(address: '203.0.113.0')
    LocationNetwork.create!(network:, location: SpecSeed.location, autopick: true, userpick: true)
    ips = network.add_ips(101, user: SpecSeed.user, environment: SpecSeed.environment)
    expect(ips.map(&:charged_environment_id).uniq).to eq([SpecSeed.environment.id])
    config = SpecSeed.user.environment_user_configs.find_by!(environment: SpecSeed.environment)
    usage = config.ipv4
    c = campaign(ips)
    2.times { c.release!(actor: SpecSeed.admin) }
    expect_staged(c, ips)
    expect(c.ip_release_request_addresses.where.not(released_at: nil)).to be_empty
    expect(config.reload.ipv4).to eq(usage)
    changes = confirmation_attr_changes(c.latest_release_attempt.transaction_chain, 'ClusterResourceUse')
    expect(changes.map { |row| row.fetch('value') }).to eq([usage - 101])
  end

  [TransactionChains::DnsZoneTransfer::Destroy, TransactionChains::DnsZone::DestroyUser].each do |destroy_chain|
    it "retains an address during pending #{destroy_chain.name} and rollback" do
      ensure_available_node_status!(SpecSeed.node)
      ip = address
      zone = create_dns_zone!(user: SpecSeed.user, source: :internal_source)
      create_dns_server_zone!(dns_zone: zone, dns_server: create_dns_server!(node: SpecSeed.node),
                              zone_type: :primary_type)
      transfer = create_dns_zone_transfer!(dns_zone: zone, host_ip_address: ip.host_ip_addresses.first,
                                           peer_type: :secondary_type)
      c = campaign([ip])
      chain, = destroy_chain.fire(destroy_chain == TransactionChains::DnsZone::DestroyUser ? zone : transfer)
      expect(transfer.reload.confirmed).to eq(:confirm_destroy)
      c.release!(actor: SpecSeed.admin)
      expect(c.latest_release_attempt.state).to eq('preparation_failed')
      expect(ip.reload.user_id).to eq(SpecSeed.user.id)
      chain.update!(state: :rollbacking)
      transfer.update!(confirmed: DnsZoneTransfer.confirmed(:confirmed))
      c.release!(actor: SpecSeed.admin)
      expect(ip.reload.user_id).to eq(SpecSeed.user.id)
      expect(item(c).released_at).to be_nil
    end
  end

  it 'retains unassigned addresses used as export client grants' do
    ip = address
    fixture = create_netif_vps_fixture!(user: SpecSeed.user)
    export, = create_export_for_dataset!(dataset_in_pool: fixture[:dataset_in_pool])
    c = campaign([ip])
    grant = ExportHost.create!(export:, ip_address: ip, rw: true, sync: true,
                               subtree_check: false, root_squash: false)
    c.release!(actor: SpecSeed.admin)
    expect(item(c).protection).to eq('exported')
    expect(item(c).last_result).to eq('exported')
    expect(ip.reload.user_id).to eq(SpecSeed.user.id)
    expect(grant.reload.ip_address_id).to eq(ip.id)
  end

  it 'returns the active batch on repeated release and preserves its initiator' do
    c = campaign([address, address])
    first = c.release!(actor: SpecSeed.admin)
    second = c.release!(actor: SpecSeed.other_user)
    expect(second.id).to eq(first.id)
    expect(second.created_by_id).to eq(SpecSeed.admin.id)
    expect(c.ip_release_attempts.count).to eq(1)
    expect_staged(c, c.ip_release_request_addresses.map(&:ip_address))
  end

  it 'preserves IPv6 prefix snapshots and releases the charged allocation units once' do
    network = SpecSeed.network_v6
    network.update!(split_prefix: 80)
    ip = create_ip_address!(network:, user: SpecSeed.user,
                            addr: '2001:db8::', prefix: 80, size: 256)
    ip.update!(charged_environment: SpecSeed.environment)
    config = SpecSeed.user.environment_user_configs.find_by!(environment: SpecSeed.environment)
    before = config.ipv6
    c = campaign([ip])
    expect(item(c).prefix).to eq(80)
    expect(item(c).size).to eq(256)
    expect(described_class.candidates(versions: [4])).not_to include(ip)
    2.times { c.release!(actor: SpecSeed.admin) }
    expect_staged(c, [ip])
    expect(config.reload.ipv6).to eq(before)
  end

  it 'removes DNS transfer grants before making an address available to another owner' do
    ensure_available_node_status!(SpecSeed.node)
    server = create_dns_server!(node: SpecSeed.node)
    ip = address
    host = ip.host_ip_addresses.first
    internal = create_dns_zone!(user: SpecSeed.user, source: :internal_source)
    external = create_dns_zone!(user: SpecSeed.user, source: :external_source, email: nil)
    [[internal, :secondary_type], [external, :primary_type]].each do |zone, peer_type|
      create_dns_server_zone!(dns_zone: zone, dns_server: server,
                              zone_type: zone.internal_source? ? :primary_type : :secondary_type)
      DnsZoneTransfer.create!(dns_zone: zone, host_ip_address: host, peer_type:,
                              confirmed: DnsZoneTransfer.confirmed(:confirmed))
    end
    c = campaign([ip])
    c.release!(actor: SpecSeed.admin)
    expect(item(c).last_result).to eq('releasing'), c.latest_release_attempt.error
    expect(ip.reload.user_id).to eq(SpecSeed.user.id)
    expect(host.dns_zone_transfers.existing).to be_empty
    expect(ip).to be_locked
    expect(item(c).cleanup_state).to eq('queued')
    expect(tx_classes(item(c).release_chain).count(Transactions::DnsServerZone::RemoveServers)).to eq(2)
  end

  it 'rejects stale host creation, PTR writes and transfer grants during release' do
    ip = address
    stale_host = ip.host_ip_addresses.first
    stale_host.ip_address.current_owner
    zone = create_dns_zone!(user: SpecSeed.user, source: :internal_source)
    transfer = DnsZoneTransfer.new(dns_zone: zone, host_ip_address: stale_host, peer_type: :secondary_type)
    c = campaign([ip])
    c.release!(actor: SpecSeed.admin)
    expect do
      VpsAdmin::API::Operations::HostIpAddress::Create.run(ip, ip.addr, actor: SpecSeed.user)
    end.to raise_error(ResourceLocked)
    expect do
      TransactionChains::DnsZone::SetReverseRecord.fire(stale_host, 'old.example.test.', actor: SpecSeed.user)
    end.to raise_error(ResourceLocked)
    expect do
      TransactionChains::DnsZoneTransfer::Create.fire(transfer)
    end.to raise_error(ResourceLocked)
  end

  it 'releases before the deadline without sending or checking mail, exactly once' do
    ip = address
    c = campaign([ip])
    config = SpecSeed.user.environment_user_configs.find_by!(environment: SpecSeed.environment)
    before = config.ipv4
    2.times { c.release!(actor: SpecSeed.admin) }
    expect_staged(c, [ip])
    expect(ip.charged_environment_id).to eq(SpecSeed.environment.id)
    expect(config.reload.ipv4).to eq(before)
    expect(c.latest_release_attempt.created_by_id).to eq(SpecSeed.admin.id)
    expect(item(c).cleanup_state).to eq('queued')
    expect(item(c).active_ip_address_id).to eq(ip.id)
    expect(c.ip_release_requests.first.notified_at).to be_nil
  end

  it 'accepts late reasons, toggles their effect and preserves administrator exemptions' do
    ip = address
    c = campaign([ip])
    c.edit!({ deadline: Time.now - 60 }, actor: SpecSeed.admin)
    request = c.ip_release_requests.first
    request.keep!(ids: [item(c).id], reason: 'Upcoming migration', actor: SpecSeed.user)
    expect(item(c).protection).to eq('kept')
    c.edit!({ allow_keep: false }, actor: SpecSeed.admin)
    expect(item(c).protection).to eq('eligible')
    c.edit!({ allow_keep: true }, actor: SpecSeed.admin)
    expect(item(c).protection).to eq('kept')
    item(c).exempt!(reason: 'Approved reservation', actor: SpecSeed.admin)
    c.edit!({ allow_keep: false }, actor: SpecSeed.admin)
    c.release!(actor: SpecSeed.admin)
    expect(ip.reload.user_id).to eq(SpecSeed.user.id)
    expect(item(c).last_result).to eq('exempted')
    item(c).exempt!(reason: nil, actor: SpecSeed.admin)
    c.release!(actor: SpecSeed.admin)
    expect_staged(c, [ip])
    expect(item(c).keep_reason).to eq('Upcoming migration')
  end

  it 'requires a reason for each selected item and rejects foreign or released items' do
    c = campaign([address])
    request = c.ip_release_requests.first
    ['', ' ', 'x' * 2001].each do |reason|
      expect { request.keep!(ids: [item(c).id], reason:, actor: SpecSeed.user) }
        .to raise_error(ActiveRecord::RecordInvalid)
    end
    expect { request.keep!(ids: [item(c).id], reason: 'Mine', actor: SpecSeed.other_user) }
      .to raise_error(described_class::Error, 'access_denied')
    expect { request.keep!(ids: [item(c).id, 999_999], reason: 'Mine', actor: SpecSeed.user) }
      .to raise_error(described_class::Error, 'invalid_addresses')
    c.release!(actor: SpecSeed.admin)
    expect { request.keep!(ids: [item(c).id], reason: 'Mine', actor: SpecSeed.user) }
      .to raise_error(described_class::Error, 'already_released')
  end

  it 'protects every assigned interface and can reevaluate an address after detachment' do
    ip = address
    c = campaign([ip])
    fixture = create_netif_vps_fixture!
    ip.update!(network_interface: fixture[:netif])
    c.release!(actor: SpecSeed.admin)
    expect(ip.reload.user_id).to eq(SpecSeed.user.id)
    expect(item(c).last_result).to eq('assigned')
    ip.update!(network_interface: nil)
    c.release!(actor: SpecSeed.admin)
    expect_staged(c, [ip])
  end

  it 'skips changed ownership and deleted records but retains snapshots' do
    first = address
    second = address
    c = campaign([first, second])
    first.update!(user: SpecSeed.other_user)
    second.destroy!
    c.release!(actor: SpecSeed.admin)
    expect(c.ip_release_request_addresses.map(&:last_result)).to eq(%w[changed changed])
    expect(c.ip_release_request_addresses.count).to eq(2)
    expect(first.reload.user_id).to eq(SpecSeed.other_user.id)
  end

  %w[soft_delete hard_delete deleted missing].each do |state|
    it "permanently excludes a #{state} owner while processing other users" do
      ip = address
      other = address(user: SpecSeed.other_user)
      c = campaign([ip, other])
      if state == 'missing'
        User.where(id: SpecSeed.user.id).delete_all
      else
        SpecSeed.user.update!(object_state: state)
      end
      c.release!(actor: SpecSeed.admin)
      excluded = item(c)
      expect(excluded.exclusion_reason).to eq('owner_deleted')
      expect(excluded.excluded_at).not_to be_nil
      expect(excluded.active_ip_address_id).to be_nil
      expect(excluded.released_at).to be_nil
      expect(ip.reload.user_id).to eq(SpecSeed.user.id)
      expect_staged(c, [other])
      unless state == 'missing'
        SpecSeed.user.update!(object_state: 'active')
        c.release!(actor: SpecSeed.admin)
        expect(ip.reload.user_id).to eq(SpecSeed.user.id)
        expect(campaign([ip])).to be_persisted
      end
    end
  end

  it 'does not treat a suspended owner as deleted' do
    ip = address
    c = campaign([ip])
    SpecSeed.user.update!(object_state: 'suspended')
    c.release!(actor: SpecSeed.admin)
    expect(item(c).last_result).to eq('releasing')
  end

  it 'does not touch a new owner or their reverse record and frees the campaign claim' do
    ip = address
    c = campaign([ip])
    ip.update!(user: SpecSeed.other_user)
    zone = create_reverse_dns_zone!
    ip.update!(reverse_dns_zone: zone)
    ptr = create_dns_record!(dns_zone: zone, name: '25', record_type: 'PTR', content: 'new-owner.example.test.')
    host = ip.host_ip_addresses.first
    host.update!(reverse_dns_record: ptr)
    config = SpecSeed.other_user.environment_user_configs.find_by!(environment: SpecSeed.environment)
    usage = config.ipv4
    2.times { c.release!(actor: SpecSeed.admin) }
    expect(item(c).exclusion_reason).to eq('owner_changed')
    expect(item(c).release_chain_id).to be_nil
    expect(ip.reload.user_id).to eq(SpecSeed.other_user.id)
    expect(config.reload.ipv4).to eq(usage)
    expect(host.reload.reverse_dns_record_id).to eq(ptr.id)
    expect(ptr.reload.content).to eq('new-owner.example.test.')
    expect(campaign([ip])).to be_persisted
  end

  it 'excludes a changed allocation even if its owner is unchanged' do
    ip = address
    c = campaign([ip])
    ip.update_columns(prefix: 31, size: 2)
    c.release!(actor: SpecSeed.admin)
    expect(item(c).exclusion_reason).to eq('allocation_changed')
    expect(ip.reload.user_id).to eq(SpecSeed.user.id)
  end

  [4, 6].each do |version|
    it "stages PTR cleanup on default IPv#{version} hosts without deleting the host" do
      ensure_available_node_status!(SpecSeed.node)
      ip = create_ip_address!(network: version == 4 ? SpecSeed.network_v4 : SpecSeed.network_v6,
                              user: SpecSeed.user, addr: version == 4 ? '192.0.2.25' : '2001:db8::')
      zone = create_reverse_dns_zone!
      ip.update!(reverse_dns_zone: zone)
      ptr = create_dns_record!(dns_zone: zone, name: '25', record_type: 'PTR', content: 'unused.example.test.')
      host = ip.host_ip_addresses.first
      host.update!(reverse_dns_record: ptr)
      c = campaign([ip])
      c.release!(actor: SpecSeed.admin)
      expect(item(c).last_result).to eq('releasing'), c.latest_release_attempt.error
      expect(ip.reload.user_id).to eq(SpecSeed.user.id)
      expect(host.reload.reverse_dns_record_id).to be_nil
      changes = confirmations_for(item(c).release_chain)
      expect(changes.any? { |row| row.class_name == 'DnsRecord' && row.row_pks == { 'id' => ptr.id } && row.confirm_type == 'destroy_type' }).to be(true)
      expect(changes.any? { |row| row.class_name == 'HostIpAddress' && row.confirm_type == 'just_destroy_type' }).to be(false)
    end
  end

  it 'retains addresses while another chain has a pending quota confirmation' do
    ip = address
    c = campaign([ip])
    fixture = create_netif_vps_fixture!
    unowned = create_ip_address!(user: nil)
    chain, = TransactionChains::NetworkInterface::AddRoute.fire(fixture[:netif], [unowned])
    expect(confirmations_for(chain).map(&:class_name)).to include('ClusterResourceUse')
    config = SpecSeed.user.environment_user_configs.find_by!(environment: SpecSeed.environment)
    before = config.ipv4
    c.release!(actor: SpecSeed.admin)
    expect(c.latest_release_attempt.state).to eq('preparation_failed')
    expect(ip.reload.user_id).to eq(SpecSeed.user.id)
    expect(config.reload.ipv4).to eq(before)
  end

  it 'aborts the complete batch on contention and retries only on an explicit release' do
    ips = [address, address]
    c = campaign(ips)
    reservation = ips.last.acquire_lock
    failed = c.release!(actor: SpecSeed.admin)
    expect(failed.state).to eq('preparation_failed')
    expect(failed.ip_count).to eq(2)
    expect(failed.error).to eq('resource_locked')
    expect(failed.blocked_resource_id).to eq(ips.last.id)
    expect(failed.transaction_chain_id).to be_nil
    expect(ips.map { |ip| ip.reload.user_id }).to eq([SpecSeed.user.id] * 2)
    expect(ips.first).not_to be_locked
    expect(SpecSeed.user).not_to be_locked
    reservation.release
    retry_attempt = c.release!(actor: SpecSeed.admin)
    expect(retry_attempt.id).not_to eq(failed.id)
    expect_staged(c, ips)
    expect(c.ip_release_attempts.count).to eq(2)
  end

  [ActiveRecord::Deadlocked, ActiveRecord::LockWaitTimeout].each do |error_class|
    it "retains the selected batch after #{error_class} rolls back preparation" do
      ips = [address, address]
      c = campaign(ips)
      allow(TransactionChains::IpRelease::Release).to receive(:fire).and_raise(error_class, 'Database contention')
      failed = c.release!(actor: SpecSeed.admin)
      expect(failed.state).to eq('preparation_failed')
      expect(failed.error).to eq('database_busy')
      expect(failed.ip_release_request_addresses.pluck(:ip_address_id)).to match_array(ips.map(&:id))
      expect(c.ip_release_attempts.count).to eq(1)
      expect(failed.transaction_chain_id).to be_nil
      expect(ips.map { |ip| ip.reload.user_id }).to eq([SpecSeed.user.id] * 2)
    end
  end

  it 'records unavailable transaction signing as a failed preparation' do
    ips = [address, address]
    c = campaign(ips)
    allow(VpsAdmin::API::TransactionSigner).to receive(:can_sign?).and_return(false)
    failed = c.release!(actor: SpecSeed.admin)
    expect(failed.state).to eq('preparation_failed')
    expect(failed.ip_count).to eq(2)
    expect(failed.error).to include('Transaction signing not enabled')
    expect(failed.transaction_chain_id).to be_nil
    expect(ips.map { |ip| ip.reload.user_id }).to eq([SpecSeed.user.id] * 2)
    expect(SpecSeed.user).not_to be_locked
  end

  it 'records a missing user quota as a failed preparation' do
    ip = address
    c = campaign([ip])
    quota = UserClusterResource.find_by!(user: SpecSeed.user, environment: SpecSeed.environment,
                                         cluster_resource: ClusterResource.find_by!(name: 'ipv4'))
    ClusterResourceUse.where(user_cluster_resource: quota).delete_all
    quota.destroy!
    failed = c.release!(actor: SpecSeed.admin)
    expect(failed.state).to eq('preparation_failed')
    expect(failed.ip_count).to eq(1)
    expect(failed.error).to include('does not have resource ipv4')
    expect(ip.reload.user_id).to eq(SpecSeed.user.id)
  end

  it 'keeps cleanup locked and references the existing chain on repeated release' do
    ip = address
    ensure_available_node_status!(SpecSeed.node)
    ip.host_ip_addresses.first.update!(user_created: true)
    c = campaign([ip])
    c.release!(actor: SpecSeed.admin)
    chain_id = item(c).release_chain_id
    expect(chain_id).not_to be_nil
    expect(ip.reload).to be_locked
    expect(item(c).cleanup_state).to eq('queued')
    c.release!(actor: SpecSeed.admin)
    expect(item(c).release_chain_id).to eq(chain_id)
    expect(Transactions::Utils::NoOp.where(transaction_chain_id: chain_id).count).to eq(2)
    expect(item(c).released_at).to be_nil
    expect(item(c).active_ip_address_id).to eq(ip.id)
    expect(item(c).protection).to eq('releasing')
    expect do
      c.ip_release_requests.first.keep!(ids: [item(c).id], reason: 'Too late', actor: SpecSeed.user)
    end.to raise_error(described_class::Error, 'already_released')
  end

  it 'keeps the user lifecycle locked until asynchronous release cleanup completes' do
    ensure_available_node_status!(SpecSeed.node)
    ip = address
    ip.host_ip_addresses.first.update!(user_created: true)
    c = campaign([ip])
    c.release!(actor: SpecSeed.admin)
    expect(item(c).protection).to eq('releasing')
    expect(SpecSeed.user).to be_locked
    expect do
      SpecSeed.user.set_object_state(:soft_delete, reason: 'Delete during cleanup')
    end.to raise_error(ResourceLocked)
    expect(SpecSeed.user.reload.object_state).to eq('active')
    expect(ip.reload.user_id).to eq(SpecSeed.user.id)
  end

  it 'requires recovery of fatal chains and rechecks retention after a rollback' do
    ips = [address, address]
    c = campaign(ips)
    attempt = c.release!(actor: SpecSeed.admin)
    chain = attempt.transaction_chain
    chain.update!(state: :fatal)
    expect(c.latest_release_attempt.state).to eq('attention')
    expect(c.can_release).to be(false)
    expect(c.release!(actor: SpecSeed.admin).id).to eq(attempt.id)
    chain.update!(state: :resolved)
    expect(c.latest_release_attempt.state).to eq('attention')
    frozen_item = item(c)
    expect(frozen_item.protection).to eq('releasing')
    expect(frozen_item.assign_ip_address_id).to be_nil
    expect do
      frozen_item.ip_release_request.keep!(ids: [frozen_item.id], reason: 'Too late', actor: SpecSeed.user)
    end.to raise_error(described_class::Error, 'already_released')
    expect do
      frozen_item.exempt!(reason: 'Too late', actor: SpecSeed.admin)
    end.to raise_error(described_class::Error, 'already_released')
    # Simulate the engine's completed rollback; runtime tests execute the
    # confirmations and verify that this leaves all ownership/quota intact.
    chain.update!(state: :failed)
    ResourceLock.where(locked_by: chain).delete_all
    kept = item(c)
    kept.ip_release_request.keep!(ids: [kept.id], reason: 'Migration', actor: SpecSeed.user)
    retry_attempt = c.release!(actor: SpecSeed.admin)
    expect(retry_attempt.id).not_to eq(attempt.id)
    expect(retry_attempt.ip_count).to eq(1)
    expect(attempt.ip_count).to eq(2)
    expect(kept.reload.protection).to eq('kept')
    expect_staged(c, [ips.last])
    # A reconciled old chain must not acquire the outcome of a later retry.
    TransactionConfirmation.joins(:parent_transaction)
                           .where(transactions: { transaction_chain_id: chain.id }).update_all(done: true)
    chain.update!(state: :resolved)
    retry_attempt.ip_release_request_addresses.update_all(released_at: Time.now)
    expect(attempt.reload.state).to eq('failed')
  end

  it 'keeps the active batch fixed after policy edits and campaign closure' do
    ips = [address, address]
    c = campaign(ips)
    attempt = c.release!(actor: SpecSeed.admin)
    c.edit!({ allow_keep: false }, actor: SpecSeed.admin)
    c.close!(actor: SpecSeed.admin)
    expect(c.release!(actor: SpecSeed.admin).id).to eq(attempt.id)
    expect_staged(c, ips)
    expect(c.can_release).to be(false)
  end

  it 'queues only explicit notices and releases without waiting for delivery' do
    ensure_available_node_status!(SpecSeed.node)
    ensure_user_mail_templates!
    ip = address
    c = campaign([ip])
    chain, = c.notify!(event: 'requested', actor: SpecSeed.admin)
    expect(tx_classes(chain)).to eq([Transactions::Mail::Send])
    request = c.ip_release_requests.first
    first_log = request.mail_log
    expect(first_log.text_plain).to include(ip.addr, "id=#{request.id}")
    expect(c.notify!(event: 'requested', actor: SpecSeed.admin).first).to be_nil
    expect { c.edit!({ allow_keep: false }, actor: SpecSeed.admin) }.not_to change(MailLog, :count)
    c.notify!(event: 'reminder', actor: SpecSeed.admin)
    expect(request.reload.mail_log_id).not_to eq(first_log.id)
    expect(request.mail_log.text_plain).not_to include('select it in vpsAdmin')
    expect(request.ip_release_request_notices.order(:id).pluck(:event)).to eq(%w[requested reminder])
    expect(request.ip_release_request_notices.first.mail_log).to eq(first_log)
    c.release!(actor: SpecSeed.admin)
    expect_staged(c, [ip])
    expect(chain.reload.state).to eq('queued')
  end

  it 'reminds only previously notified users about addresses still eligible under current policy' do
    ensure_available_node_status!(SpecSeed.node)
    ensure_user_mail_templates!
    ips = [20, 200, 201, 202, 203, 204].map do |last_octet|
      create_ip_address!(user: SpecSeed.user, addr: "192.0.2.#{last_octet}")
    end
    c = campaign(ips)
    expect { c.notify!(event: 'reminder', actor: SpecSeed.admin) }.not_to change(MailLog, :count)
    c.notify!(event: 'requested', actor: SpecSeed.admin)
    request = c.ip_release_requests.first
    entries = request.ip_release_request_addresses.order(:id).to_a
    request.keep!(ids: [entries[0].id], reason: 'Needed for migration', actor: SpecSeed.user)
    entries[1].exempt!(reason: 'Reserved', actor: SpecSeed.admin)
    ips[2].update!(network_interface: create_netif_vps_fixture![:netif])
    ips[3].update!(user: SpecSeed.other_user)
    ips[4].destroy!
    2.times { c.notify!(event: 'reminder', actor: SpecSeed.admin) }
    expect(request.ip_release_request_notices.pluck(:event)).to eq(%w[requested reminder reminder])
    mail = request.reload.mail_log
    expect(mail.subject).to eq('Reminder: unused IP address planned for release')
    [mail.text_plain, mail.text_html].each do |body|
      expect(body.gsub(/\s+/, ' ')).to include('IP address below, which is still unassigned')
    end
    expect(mail.text_plain).to include("#{ips[5].addr}/#{ips[5].prefix}")
    ips.take(5).each { |ip| expect(mail.text_plain).not_to include("#{ip.addr}/#{ip.prefix}") }
    c.edit!({ allow_keep: false }, actor: SpecSeed.admin)
    c.notify!(event: 'reminder', actor: SpecSeed.admin)
    expect(request.reload.mail_log.text_plain).to include(
      "#{ips[0].addr}/#{ips[0].prefix}", "#{ips[5].addr}/#{ips[5].prefix}"
    )
    c.edit!({ allow_keep: true }, actor: SpecSeed.admin)
    entries[5].exempt!(reason: 'Reserved', actor: SpecSeed.admin)
    expect { c.notify!(event: 'reminder', actor: SpecSeed.admin) }.not_to change(MailLog, :count)
  end

  it 'omits invalid addresses from initial notices and does not notify deleted users' do
    ensure_available_node_status!(SpecSeed.node)
    ensure_user_mail_templates!
    first = create_ip_address!(user: SpecSeed.user, addr: '192.0.2.20')
    second = create_ip_address!(user: SpecSeed.user, addr: '192.0.2.200')
    third = create_ip_address!(user: SpecSeed.other_user, addr: '192.0.2.201')
    c = campaign([first, second, third])
    first.update!(user: SpecSeed.other_user)
    SpecSeed.other_user.update!(object_state: 'soft_delete')
    c.notify!(event: 'requested', actor: SpecSeed.admin)
    expect(IpReleaseRequestNotice.count).to eq(1)
    mail = c.ip_release_requests.find_by!(user_id: SpecSeed.user.id).mail_log
    expect(mail.text_plain).to include("#{second.addr}/#{second.prefix}")
    expect(mail.text_plain).not_to include("#{first.addr}/#{first.prefix}", "#{third.addr}/#{third.prefix}")
  end

  it 'renders singular and plural subjects, text and HTML for each message selection' do
    IpReleaseRequestAddress.define_attribute_methods
    %w[requested reminder].product([1, 2, 5], [true, false], [true, false]).each do |event, count, allow_keep, public_ipv4|
      addresses = Array.new(count) do |i|
        instance_double(IpReleaseRequestAddress, address: "192.0.2.#{i + 20}", prefix: 32,
                                                 location_label: '<Prague & test>', public_ipv4?: public_ipv4)
      end
      builder = MailTemplateTranslation::TemplateBuilder.new({
        user: SpecSeed.user, addresses:, campaign: instance_double(described_class, deadline: Time.utc(2030, 9, 16), allow_keep:),
        request: instance_double(IpReleaseRequest, id: 123), webui_url: 'https://vpsadmin.example.test'
      })
      root = File.expand_path("../../notification_templates/templates/ip_release_#{event}/email", __dir__)
      subject = builder.build(File.read(File.join(root, 'en.subject.erb'))).strip
      expect(subject).to eq("#{event == 'reminder' ? 'Reminder: unused' : 'Unused'} IP #{count == 1 ? 'address' : 'addresses'} planned for release")
      %w[text html].each do |format|
        body = builder.build(File.read(File.join(root, "en.#{format}.erb"))).gsub(/\s+/, ' ')
        expect(body).to include(count == 1 ? 'If you no longer need this address' : 'If you no longer need these addresses')
        expect(body).to include(count == 1 ? 'options for keeping it' : 'options for keeping them')
        expect(body.include?('select it in vpsAdmin')).to eq(allow_keep)
        expect(body.include?('Public IPv4 addresses are a scarce resource.')).to eq(public_ipv4)
        addresses.each { |entry| expect(body).to include(entry.address) }
        if format == 'html'
          expect(body).to include('(&lt;Prague &amp; test&gt;)', 'Open in vpsAdmin')
          expect(body.scan('<li>').length).to eq(count)
        else
          expect(body).to include('(<Prague & test>)')
        end
      end
    end
  end

  [[4], [6], [4, 6]].each do |versions|
    it "renders text and escaped HTML for IPv#{versions.join('/')} addresses" do
      ensure_available_node_status!(SpecSeed.node)
      ensure_user_mail_templates!
      SpecSeed.location.update!(label: '<Prague & test>')
      ips = versions.map do |v|
        network = v == 4 ? SpecSeed.network_v4 : SpecSeed.network_v6
        network.update!(primary_location: SpecSeed.location)
        create_ip_address!(network:, user: SpecSeed.user, addr: v == 4 ? '192.0.2.25' : '2001:db8::')
      end
      c = campaign(ips)
      c.notify!(event: 'requested', actor: SpecSeed.admin)
      mail = c.ip_release_requests.first.mail_log
      expect(mail.text_plain).to include('(<Prague & test>)', 'do not need to reply')
      expect(mail.text_html).to include('(&lt;Prague &amp; test&gt;)', 'Open in vpsAdmin', '&amp;action=request&amp;id=')
      expect(mail.text_html).not_to include('<Prague', 'Please respond', 'releases the addresses manually')
      [mail.text_plain, mail.text_html].each do |body|
        expect(body.include?('Public IPv4 addresses are a scarce resource.')).to eq(versions.include?(4))
      end
    end
  end

  it 'renders available locations or an unavailable label with a past planned date' do
    ensure_available_node_status!(SpecSeed.node)
    ensure_user_mail_templates!
    ip = address
    ip.network.update!(primary_location: nil)
    LocationNetwork.find_or_create_by!(network: ip.network, location: SpecSeed.other_location)
    c = campaign([ip])
    c.edit!({ deadline: Time.utc(2020, 1, 2) }, actor: SpecSeed.admin)
    c.notify!(event: 'requested', actor: SpecSeed.admin)
    request = c.ip_release_requests.first
    expect(request.mail_log.text_plain).to include("(#{SpecSeed.location.label}, #{SpecSeed.other_location.label})")
    ip.network.location_networks.destroy_all
    c.notify!(event: 'reminder', actor: SpecSeed.admin)
    expect(request.reload.mail_log.text_plain).to include('(location unavailable)', '2020-01-02')
    expect(request.mail_log.text_html).to include('(location unavailable)', '2020-01-02')
  end

  it 'closes a campaign without restoring released IPs and frees pending claims' do
    ip = address
    c = campaign([ip])
    c.close!(actor: SpecSeed.admin)
    expect(item(c).active_ip_address_id).to be_nil
    expect { c.release!(actor: SpecSeed.admin) }.to raise_error(described_class::Error, 'closed')
    expect { c.edit!({ allow_keep: false }, actor: SpecSeed.admin) }.to raise_error(described_class::Error, 'closed')
    expect(campaign([ip])).to be_persisted
  end

  it 'filters public and private families, owners and overlapping locations without duplicates' do
    public_ip = address
    private_net = SpecSeed.network_v4.dup
    private_net.update!(address: '10.23.0.0', role: :private_access)
    LocationNetwork.create!(network: private_net, location: SpecSeed.location)
    LocationNetwork.create!(network: private_net, location: SpecSeed.other_location)
    private_ip = create_ip_address!(network: private_net, addr: '10.23.0.10', user: SpecSeed.user)
    v6 = create_ip_address!(network: SpecSeed.network_v6, addr: '2001:db8::abcd', user: SpecSeed.other_user)
    expect(described_class.candidates).to include(public_ip)
    expect(described_class.candidates).not_to include(private_ip, v6)
    filters = { versions: [4, 6], access: 'all', networks: [private_net.id, SpecSeed.network_v6.id],
                locations: [SpecSeed.location.id, SpecSeed.other_location.id] }
    expect(described_class.candidates(filters).pluck(:id)).to contain_exactly(private_ip.id, v6.id)
    expect(described_class.candidates(filters.merge(user: SpecSeed.user)).pluck(:id)).to eq([private_ip.id])
    expect(described_class.candidates(access: 'private_access').pluck(:id)).to eq([private_ip.id])
    config = SpecSeed.user.environment_user_configs.find_by!(environment: SpecSeed.environment)
    before_private = config.ipv4_private
    before_public = config.ipv4
    c = campaign([private_ip])
    ensure_available_node_status!(SpecSeed.node)
    ensure_user_mail_templates!
    c.notify!(event: 'requested', actor: SpecSeed.admin)
    mail = c.ip_release_requests.first.mail_log
    expect(mail.text_plain).not_to include('Public IPv4 addresses are a scarce resource.')
    expect(mail.text_html).not_to include('Public IPv4 addresses are a scarce resource.')
    2.times { c.release!(actor: SpecSeed.admin) }
    expect_staged(c, [private_ip])
    expect(config.reload.ipv4_private).to eq(before_private)
    expect(config.ipv4).to eq(before_public)
  end

  it 'excludes export grants and host assignments from both preview and creation' do
    ips = [address, address]
    fixture = create_netif_vps_fixture!(user: SpecSeed.user)
    export, = create_export_for_dataset!(dataset_in_pool: fixture[:dataset_in_pool])
    ExportHost.create!(export:, ip_address: ips.first, rw: true, sync: true, subtree_check: false, root_squash: false)
    ips.last.host_ip_addresses.first.update!(order: 0)
    expect(described_class.candidates.pluck(:id)).not_to include(*ips.map(&:id))
    ips.each do |ip|
      expect { campaign([ip]) }.to raise_error(described_class::Error, 'ineligible_addresses')
    end
  end

  it 'offers notice actions by eligible recipient and initial-notice history' do
    ensure_available_node_status!(SpecSeed.node)
    ensure_user_mail_templates!
    c = campaign([address, address(user: SpecSeed.other_user)])
    SpecSeed.other_user.update!(mailer_enabled: false)
    expect(c.can_send_initial_notices).to be(true)
    expect(c.can_send_reminders).to be(false)
    expect(c.can_release).to be(true)
    c.notify!(event: 'reminder', actor: SpecSeed.admin)
    expect(IpReleaseRequestNotice.count).to eq(0)
    c.notify!(event: 'requested', actor: SpecSeed.admin)
    expect(c.can_send_initial_notices).to be(false)
    expect(c.can_send_reminders).to be(true)
    SpecSeed.other_user.update!(mailer_enabled: true)
    expect(c.can_send_initial_notices).to be(true)
    c.notify!(event: 'requested', actor: SpecSeed.admin)
    expect(IpReleaseRequestNotice.count).to eq(2)
    expect(c.can_send_initial_notices).to be(false)
    c.exempt!(ids: c.ip_release_request_addresses.pluck(:id), reason: 'Keep', actor: SpecSeed.admin)
    expect(c.can_send_reminders).to be(false)
    expect(c.can_release).to be(false)
    c.close!(actor: SpecSeed.admin)
    expect(c.can_send_initial_notices).to be(false)
    expect(c.can_send_reminders).to be(false)
    expect(c.can_release).to be(false)
  end
end
