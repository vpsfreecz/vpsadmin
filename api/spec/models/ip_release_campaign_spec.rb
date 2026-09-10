require 'spec_helper'

RSpec.describe IpReleaseCampaign do
  around do |example|
    with_current_context { example.run }
  end

  before { unlock_transaction_signer! }

  def address(user: SpecSeed.user)
    create_ip_address!(user:)
  end

  def campaign(ips, **attrs)
    described_class.create_selected!(ids: ips.map(&:id), actor: SpecSeed.admin,
                                     label: 'Recover unused IPv4', deadline: Time.now + 604_800,
                                     **attrs)
  end

  def item(c)
    c.ip_release_request_addresses.first
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

  it 'rejects oversized campaigns before saving any selection' do
    expect do
      described_class.create_selected!(ids: (1..101).to_a, actor: SpecSeed.admin,
                                       label: 'Too large', deadline: Time.now)
    end.to raise_error(described_class::Error, 'too_many_addresses')
    expect(described_class.count).to eq(0)
  end

  it 'reports legacy missing accounting provenance without changing ownership or quota' do
    ip = address
    ip.update!(charged_environment: nil)
    config = SpecSeed.user.environment_user_configs.find_by!(environment: SpecSeed.environment)
    usage = config.ipv4
    c = campaign([ip])
    c.release!(actor: SpecSeed.admin)
    expect(item(c).last_result).to eq('failed')
    expect(item(c).last_error).to include('reconcile its accounting')
    expect(ip.reload.user_id).to eq(SpecSeed.user.id)
    expect(config.reload.ipv4).to eq(usage)
  end

  it 'releases a full campaign populated by managed network additions exactly once' do
    network = SpecSeed.network_v4.dup
    network.update!(address: '203.0.113.0')
    LocationNetwork.create!(network:, location: SpecSeed.location, autopick: true, userpick: true)
    ips = network.add_ips(100, user: SpecSeed.user, environment: SpecSeed.environment)
    expect(ips.map(&:charged_environment_id).uniq).to eq([SpecSeed.environment.id])
    config = SpecSeed.user.environment_user_configs.find_by!(environment: SpecSeed.environment)
    usage = config.ipv4
    c = campaign(ips)
    2.times { c.release!(actor: SpecSeed.admin) }
    expect(c.ip_release_request_addresses.where.not(released_at: nil).count).to eq(100)
    expect(IpAddress.where(id: ips.map(&:id)).where.not(user_id: nil)).to be_empty
    expect(config.reload.ipv4).to eq(usage - 100)
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
      expect(item(c).last_result).to eq('failed')
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

  it 'does not overwrite a newer active attempt with an older staging failure' do
    ensure_available_node_status!(SpecSeed.node)
    ip = address
    ip.host_ip_addresses.first.update!(user_created: true)
    c = campaign([ip])
    target = item(c)
    first = true
    allow(TransactionChains::IpRelease::Release).to receive(:fire).and_wrap_original do |original, *args|
      if first
        first = false
        raise ResourceLocked.new(ip, 'older staging failure')
      end
      original.call(*args)
    end
    allow(target.ip_release_campaign).to receive(:with_lock).and_wrap_original do |original, **kwargs, &block|
      IpReleaseRequestAddress.find(target.id).release!(actor: SpecSeed.admin)
      original.call(**kwargs, &block)
    end
    target.release!(actor: SpecSeed.admin)
    expect(target.reload.protection).to eq('releasing')
    expect(target.last_result).to eq('releasing')
    expect(target.last_error).to be_nil
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
    expect(described_class.candidates(version: 4)).not_to include(ip)
    2.times { c.release!(actor: SpecSeed.admin) }
    expect(ip.reload.user_id).to be_nil
    expect(config.reload.ipv6).to eq(before - 256)
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
    expect(item(c).last_result).to eq('releasing'), item(c).last_error
    expect(ip.reload.user_id).to eq(SpecSeed.user.id)
    expect(host.dns_zone_transfers.existing).to be_empty
    expect(ip).to be_locked
    expect(item(c).cleanup_state).to eq('queued')
    expect(tx_classes(item(c).release_chain).count(Transactions::DnsServerZone::RemoveServers)).to eq(2)
  end

  it 'rejects stale host creation, PTR writes and transfer grants after release' do
    ip = address
    stale_host = ip.host_ip_addresses.first
    stale_host.ip_address.current_owner
    zone = create_dns_zone!(user: SpecSeed.user, source: :internal_source)
    transfer = DnsZoneTransfer.new(dns_zone: zone, host_ip_address: stale_host, peer_type: :secondary_type)
    campaign([ip]).release!(actor: SpecSeed.admin)
    expect do
      VpsAdmin::API::Operations::HostIpAddress::Create.run(ip, ip.addr, actor: SpecSeed.user)
    end.to raise_error(VpsAdmin::API::Exceptions::OperationError)
    expect do
      TransactionChains::DnsZone::SetReverseRecord.fire(stale_host, 'old.example.test.', actor: SpecSeed.user)
    end.to raise_error(VpsAdmin::API::Exceptions::OperationError)
    expect do
      TransactionChains::DnsZoneTransfer::Create.fire(transfer)
    end.to raise_error(ActiveRecord::RecordInvalid)
  end

  it 'releases before the deadline without sending or checking mail, exactly once' do
    ip = address
    c = campaign([ip])
    config = SpecSeed.user.environment_user_configs.find_by!(environment: SpecSeed.environment)
    before = config.ipv4
    2.times { c.release!(actor: SpecSeed.admin) }
    expect(ip.reload.user_id).to be_nil
    expect(ip.charged_environment_id).to be_nil
    expect(config.reload.ipv4).to eq(before - ip.size)
    expect(item(c).released_by_id).to eq(SpecSeed.admin.id)
    expect(item(c).cleanup_state).to eq('done')
    expect(item(c).active_ip_address_id).to be_nil
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
    expect(ip.reload.user_id).to be_nil
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
    expect(ip.reload.user_id).to be_nil
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
      expect(other.reload.user_id).to be_nil
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
    expect(item(c).last_result).to eq('released')
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
      expect(item(c).last_result).to eq('releasing'), item(c).last_error
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
    expect(item(c).last_result).to eq('failed')
    expect(ip.reload.user_id).to eq(SpecSeed.user.id)
    expect(config.reload.ipv4).to eq(before)
  end

  it 'reports a locked item and releases other eligible items' do
    first = address
    second = address
    c = campaign([first, second])
    lock = first.acquire_lock
    c.release!(actor: SpecSeed.admin)
    expect(first.reload.user_id).to eq(SpecSeed.user.id)
    expect(second.reload.user_id).to be_nil
    expect(item(c).last_result).to eq('failed')
    lock.release
    c.release!(actor: SpecSeed.admin)
    expect(first.reload.user_id).to be_nil
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
    expect(ip.reload.user_id).to be_nil
    expect(chain.reload.state).to eq('queued')
  end

  it 'reminds only previously notified users about addresses still eligible under current policy' do
    ensure_available_node_status!(SpecSeed.node)
    ensure_user_mail_templates!
    ips = Array.new(6) { address }
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
    expect(mail.text_plain).to include(ips[5].addr)
    ips.take(5).each { |ip| expect(mail.text_plain).not_to include(ip.addr) }
    c.edit!({ allow_keep: false }, actor: SpecSeed.admin)
    c.notify!(event: 'reminder', actor: SpecSeed.admin)
    expect(request.reload.mail_log.text_plain).to include(ips[0].addr, ips[5].addr)
    c.edit!({ allow_keep: true }, actor: SpecSeed.admin)
    entries[5].exempt!(reason: 'Reserved', actor: SpecSeed.admin)
    expect { c.notify!(event: 'reminder', actor: SpecSeed.admin) }.not_to change(MailLog, :count)
  end

  it 'omits invalid addresses from initial notices and does not notify deleted users' do
    ensure_available_node_status!(SpecSeed.node)
    ensure_user_mail_templates!
    first = address
    second = address
    third = address(user: SpecSeed.other_user)
    c = campaign([first, second, third])
    first.update!(user: SpecSeed.other_user)
    SpecSeed.other_user.update!(object_state: 'soft_delete')
    c.notify!(event: 'requested', actor: SpecSeed.admin)
    expect(IpReleaseRequestNotice.count).to eq(1)
    mail = c.ip_release_requests.find_by!(user_id: SpecSeed.user.id).mail_log
    expect(mail.text_plain).to include(second.addr)
    expect(mail.text_plain).not_to include(first.addr, third.addr)
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
end
