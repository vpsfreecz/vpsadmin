# frozen_string_literal: true

require 'spec_helper'
require 'timeout'

RSpec.describe TransactionChains::DnsServer::Update do
  around do |example|
    with_current_context(user: SpecSeed.user) do |session|
      example.run
    ensure
      session.destroy! if example.metadata[:no_transaction]
    end
  end

  def source_fixture
    server = create_dns_server!(
      node: SpecSeed.node, ipv4_addr: '192.0.2.53', user_dns_zone_type: :secondary_type
    )
    peer = create_dns_server!(
      node: SpecSeed.other_node, ipv4_addr: '192.0.2.54', user_dns_zone_type: :secondary_type
    )
    zone = create_dns_zone!(user: SpecSeed.user, source: :external_source)
    server_zone = create_dns_server_zone!(dns_zone: zone, dns_server: server, zone_type: :secondary_type)
    peer_zone = create_dns_server_zone!(dns_zone: zone, dns_server: peer, zone_type: :secondary_type)
    ip = create_ip_address!(user: SpecSeed.user)
    transfer = create_dns_zone_transfer!(
      dns_zone: zone, host_ip_address: ip.host_ip_addresses.take!, peer_type: :primary_type,
      dns_tsig_key: create_dns_tsig_key!(user: SpecSeed.user)
    )
    [server, zone, server_zone, peer_zone, transfer]
  end

  def rollback_edits(chain)
    confirmations_for(chain).where(confirm_type: :edit_before_type).each do |confirmation|
      confirmation.class_name.constantize.where(confirmation.row_pks).update_all(confirmation.attr_changes)
    end
    chain.release_locks
  end

  it 'reserves all peers in one chain and restores directional source and generation on rollback' do
    server, zone, server_zone, peer_zone, = source_fixture
    original_generation = zone.primary_transfer_generation
    original_start = zone.primary_transfer_tracking_started_at.to_i
    original_configs = [server_zone, peer_zone].to_h { |entry| [entry.id, entry.configuration_attrs.deep_stringify_keys] }

    chain, updated = described_class.fire(server, ipv4_addr: nil, ipv6_addr: '2001:db8::53', hidden: true)
    generation = zone.reload.primary_transfer_generation

    expect(updated.reload.ipv4_addr).to be_nil
    expect(generation).not_to eq(original_generation)
    expect(TransactionChain.where(name: described_class.chain_name).count).to eq(1)
    expect(TransactionChain.where(name: TransactionChains::DnsServerZone::RefreshConfiguration.chain_name)).to be_empty
    expect(server.get_current_lock.locked_by).to eq(chain)
    expect(zone.get_current_lock.locked_by).to eq(chain)
    [server_zone, peer_zone].each_with_index do |entry, index|
      payload = tx_payload(chain, Transactions::DnsServerZone::Update, nth: index)
      source_addrs = if index == 0
                       { 'ipv4' => nil, 'ipv6' => '2001:db8::53' }
                     else
                       { 'ipv4' => '192.0.2.54', 'ipv6' => nil }
                     end
      expect(payload.fetch('original')).to eq(original_configs.fetch(entry.id))
      expect(payload.fetch('new')).to include(
        'primary_transfer_generation' => generation,
        'primary_transfer_tracking_started_at' => zone.primary_transfer_tracking_started_at.to_i,
        'probe_source_addrs' => source_addrs
      )
    end

    chain.update!(state: :fatal)
    expect(zone.get_current_lock.locked_by).to eq(chain)
    rollback_edits(chain)

    expect(server.reload).to have_attributes(ipv4_addr: '192.0.2.53', ipv6_addr: nil, hidden: false)
    expect(zone.reload.primary_transfer_generation).to eq(original_generation)
    expect(zone.primary_transfer_tracking_started_at.to_i).to eq(original_start)
    expect(server.get_current_lock).to be_nil
    expect(zone.get_current_lock).to be_nil
    expect(zone.primary_transfer_failure_resolution).to be_nil
    [server_zone, peer_zone].each_with_index do |entry, index|
      expect(entry.reload.configuration_attrs.deep_stringify_keys).to eq(
        tx_payload(chain, Transactions::DnsServerZone::Update, nth: index).fetch('original')
      )
    end
  end

  it 'cannot refresh a pending primary removal and excludes it after terminal deletion' do
    server, zone, server_zone, _peer_zone, transfer = source_fixture
    removal, = TransactionChains::DnsZoneTransfer::Destroy.fire(transfer)
    generation = zone.reload.primary_transfer_generation
    tx_count = Transaction.count
    expect((server_zone.reload.primaries + server_zone.secondaries).map { |entry| entry.fetch(:ip_addr) })
      .not_to include(transfer.ip_addr)

    expect { described_class.fire(server, ipv4_addr: '192.0.2.55') }.to raise_error(ResourceLocked)
    expect { TransactionChains::DnsServerZone::RefreshConfiguration.fire(server_zone) }.to raise_error(ResourceLocked)
    expect(server.reload.ipv4_addr).to eq('192.0.2.53')
    expect(zone.reload.primary_transfer_generation).to eq(generation)
    expect(Transaction.count).to eq(tx_count)
    expect(server.get_current_lock).to be_nil

    # Terminal destroy is raw confirmation deletion; resource locks survive
    # until that chain's established terminal release.
    transfer.delete
    removal.release_locks
    refresh, = TransactionChains::DnsServerZone::RefreshConfiguration.fire(server_zone)
    payload = tx_payload(refresh, Transactions::DnsServerZone::Update).fetch('new')
    expect((payload.fetch('primaries') + payload.fetch('secondaries')).map { |entry| entry.fetch('ip_addr') })
      .not_to include(transfer.ip_addr)
  end

  it 'cannot restore a pending peer allow-transfer endpoint after terminal deletion' do
    server, _zone, server_zone, peer_zone, = source_fixture
    peer_addr = peer_zone.ip_addr
    removal, = TransactionChains::DnsServerZone::Destroy.fire(peer_zone)

    expect { described_class.fire(server, ipv4_addr: '192.0.2.55') }.to raise_error(ResourceLocked)
    expect((server_zone.reload.primaries + server_zone.secondaries).map { |entry| entry.fetch(:ip_addr) })
      .not_to include(peer_addr)
    peer_zone.delete
    removal.release_locks
    refresh, = TransactionChains::DnsServerZone::RefreshConfiguration.fire(server_zone)
    attrs = tx_payload(refresh, Transactions::DnsServerZone::Update).fetch('new')
    expect((attrs.fetch('primaries') + attrs.fetch('secondaries')).map { |entry| entry.fetch('ip_addr') })
      .not_to include(peer_addr)
  end

  it 'cannot overtake deferred disown and refreshes retained endpoints after its rollback' do
    server, _zone, server_zone, _peer_zone, transfer = source_fixture
    ip = transfer.host_ip_address.ip_address
    config = SpecSeed.user.environment_user_configs.find_by!(environment: ip.charged_environment)
    quota = config.ipv4
    disown, = TransactionChains::Ip::Disown.fire(ips: [ip], defer: true)

    expect(transfer.reload.confirmed).to eq(:confirm_destroy)
    expect { described_class.fire(server, ipv4_addr: '192.0.2.55') }.to raise_error(ResourceLocked)
    expect(ip.reload.user_id).to eq(SpecSeed.user.id)
    expect(config.reload.ipv4).to eq(quota)
    transfer.update_columns(confirmed: DnsZoneTransfer.confirmed(:confirmed))
    disown.release_locks

    refresh, = TransactionChains::DnsServerZone::RefreshConfiguration.fire(server_zone)
    expect(tx_payload(refresh, Transactions::DnsServerZone::Update).dig('new', 'primaries'))
      .to include(include('id' => transfer.id, 'ip_addr' => transfer.ip_addr))
  end

  it 'discovers a whole zone pending destruction before filtering emitted configuration' do
    server, zone, = source_fixture
    removal, = TransactionChains::DnsZone::DestroyUser.fire(zone)
    expect(zone.reload.confirmed).to eq(:confirm_destroy)

    expect { described_class.fire(server, ipv4_addr: '192.0.2.55') }.to raise_error(ResourceLocked)
    expect(server.reload.ipv4_addr).to eq('192.0.2.53')
    expect(zone.get_current_lock.locked_by).to eq(removal)
  end

  it 'blocks reverse lifecycle changes and a new zone join until source rollback completes' do
    server, zone, server_zone, _peer_zone, transfer = source_fixture
    update, = described_class.fire(server, ipv4_addr: '192.0.2.55')

    expect { TransactionChains::DnsZoneTransfer::Destroy.fire(transfer) }.to raise_error(ResourceLocked)
    expect { TransactionChains::DnsZone::Update.fire(zone, enabled: false) }.to raise_error(ResourceLocked)
    expect { TransactionChains::DnsServerZone::Destroy.fire(server_zone) }.to raise_error(ResourceLocked)
    fresh_zone = create_dns_zone!(user: SpecSeed.user, source: :external_source)
    join = DnsServerZone.new(dns_zone: fresh_zone, dns_server: server, zone_type: :secondary_type)
    expect { TransactionChains::DnsServerZone::Create.fire(join) }.to raise_error(ResourceLocked)
    new_zone = DnsZone.new(
      user: SpecSeed.user, name: "source-join-#{SecureRandom.hex(4)}.example.test.",
      zone_source: :external_source, zone_role: :forward_role, default_ttl: 3600, enabled: true, label: ''
    )
    expect { TransactionChains::DnsZone::CreateUser.fire(new_zone) }.to raise_error(ResourceLocked)
    expect(new_zone).not_to be_persisted

    rollback_edits(update)
    created, = TransactionChains::DnsServerZone::Create.fire(join)
    expect(tx_payload(created, Transactions::DnsServerZone::Create).fetch('probe_source_addrs'))
      .to include('ipv4' => '192.0.2.53', 'ipv6' => nil)
  end

  it 'cannot mutate a source while server-zone creation owns its server and zone' do
    server = create_dns_server!(node: SpecSeed.node, user_dns_zone_type: :secondary_type)
    zone = create_dns_zone!(user: SpecSeed.user, source: :external_source)
    entry = DnsServerZone.new(dns_server: server, dns_zone: zone, zone_type: :secondary_type)
    creation, = TransactionChains::DnsServerZone::Create.fire(entry)

    expect(entry.confirmed).to eq(:confirm_create)
    expect { described_class.fire(server, ipv4_addr: '192.0.2.55') }.to raise_error(ResourceLocked)
    expect(server.get_current_lock.locked_by).to eq(creation)
    expect(zone.get_current_lock.locked_by).to eq(creation)
  end

  it 'finishes no-peer source and nonsource edits without retaining a reservation' do
    server = create_dns_server!(node: SpecSeed.node)
    chain, = described_class.fire(server, ipv4_addr: '192.0.2.55')
    expect(chain).to be_nil
    expect(server.get_current_lock).to be_nil
    chain, = described_class.fire(server, hidden: true)
    expect(chain).to be_nil
    expect(server.reload.hidden).to be(true)
    expect(server.get_current_lock).to be_nil
  end

  it 'creates a new user zone using the reserved servers current configuration' do
    server = create_dns_server!(node: SpecSeed.node, user_dns_zone_type: :secondary_type)
    zone = DnsZone.new(
      user: SpecSeed.user, name: "source-create-#{SecureRandom.hex(4)}.example.test.",
      zone_source: :external_source, zone_role: :forward_role, default_ttl: 3600, enabled: true, label: ''
    )
    chain, = TransactionChains::DnsZone::CreateUser.fire(zone)

    expect(server.get_current_lock.locked_by).to eq(chain)
    expect(zone.get_current_lock.locked_by).to eq(chain)
    payload = tx_payload(chain, Transactions::DnsServerZone::Create)
    expect(payload.fetch('primary_transfer_generation')).to eq(zone.reload.primary_transfer_generation)
    expect(payload.fetch('probe_source_addrs')).to include('ipv4' => server.ipv4_addr)
  end

  it 'uses fresh root discovery and serializes concurrent peer source updates', :no_transaction do
    servers = [SpecSeed.node, SpecSeed.other_node].map do |node|
      create_dns_server!(node:, user_dns_zone_type: :secondary_type)
    end
    zone = create_dns_zone!(user: SpecSeed.user, source: :external_source)
    preloaded = DnsServer.find(servers.first.id)
    # These joins commit after the caller loaded the server, but before the
    # source chain starts its fresh root transaction/discovery view.
    servers.each { |server| create_dns_server_zone!(dns_zone: zone, dns_server: server, zone_type: :secondary_type) }
    first_reserved = Queue.new
    second_reserved = Queue.new
    resume = Queue.new
    workers = []
    allow(DnsServerZone).to receive(:lock_configuration).and_wrap_original do |original, zones, **kwargs|
      if Thread.current[:dns_source_first]
        first_reserved << true
        resume.pop
      end
      original.call(zones, **kwargs)
    end
    allow(servers.last).to receive(:acquire_lock).and_wrap_original do |original, *args, **kwargs|
      result = original.call(*args, **kwargs)
      second_reserved << true
      result
    end
    workers << Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        Thread.current[:dns_source_first] = true
        described_class.fire(preloaded, ipv4_addr: '192.0.2.240').first
      end
    end
    Timeout.timeout(20) { first_reserved.pop }
    workers << Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        described_class.fire(servers.last, ipv4_addr: '192.0.2.241')
      rescue ResourceLocked => e
        e
      end
    end
    Timeout.timeout(20) { second_reserved.pop }
    resume << true
    results = Timeout.timeout(20) { workers.map(&:value) }

    expect(results.first).to be_a(TransactionChain)
    expect(results.last).to be_a(ResourceLocked)
    expect(results.first.transactions.where(handle: Transactions::DnsServerZone::Update.t_type).count).to eq(2)
    expect(zone.get_current_lock.locked_by_id).to eq(results.first.id)
  ensure
    resume << true if resume
    workers&.each { |worker| worker.join(25) || worker.kill.join }
    if servers
      chain_ids = ResourceLock.where(resource: 'DnsServer', row_id: servers.map(&:id)).pluck(:locked_by_id)
      transaction_ids = Transaction.where(transaction_chain_id: chain_ids).pluck(:id)
      TransactionConfirmation.where(transaction_id: transaction_ids).delete_all
      TransactionChainConcern.where(transaction_chain_id: chain_ids).delete_all
      Transaction.where(id: transaction_ids).delete_all
      ResourceLock.where(locked_by_type: 'TransactionChain', locked_by_id: chain_ids).delete_all
      TransactionChain.where(id: chain_ids).delete_all
      DnsServerZone.where(dns_zone_id: zone&.id).delete_all
      DnsZone.where(id: zone&.id).delete_all
      DnsServer.where(id: servers.map(&:id)).delete_all
    end
  end
end
