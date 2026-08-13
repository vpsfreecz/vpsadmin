# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Tasks::Dns do
  let(:task) { described_class.new }

  def create_reverse_fixture!(server_count: 1)
    network = create_private_network!(location: SpecSeed.location, purpose: :vps)
    ip = create_ipv4_address_in_network!(network: network, location: SpecSeed.location)
    host_ip = ip.host_ip_addresses.take!
    zone = create_reverse_dns_zone!(
      name: "reverse-#{SecureRandom.hex(4)}.example.test.",
      network_address: network.address,
      network_prefix: network.prefix
    )
    record = create_dns_record!(
      dns_zone: zone,
      name: '25',
      record_type: 'PTR',
      content: 'host.example.test.'
    )
    host_ip.update!(reverse_dns_record: record)
    servers = server_count.times.map do |i|
      server = create_dns_server!(
        node: SpecSeed.node,
        name: "ns-rev-#{i}-#{SecureRandom.hex(4)}"
      )
      create_dns_server_zone!(dns_zone: zone, dns_server: server)
      server
    end

    { host_ip: host_ip, record: record, servers: servers }
  end

  def stub_ptr_query
    allow(VpsAdmin::API::DnsResolver).to receive(:open) do |addrs, &block|
      resolver = Object.new
      allow(resolver).to receive(:query_ptr) { |ip| yield(addrs, ip) }
      block.call(resolver)
    end
  end

  it 'counts correct PTR answers as successful' do
    fixture = create_reverse_fixture!
    stub_ptr_query { |_addrs, _ip| fixture.fetch(:record).content }

    expect { task.check_reverse_records }.to output(/1 records ok/).to_stdout
  end

  it 'retries ResolvError answers up to three times' do
    fixture = create_reverse_fixture!
    attempts = 0
    allow(task).to receive(:sleep)
    stub_ptr_query do |_addrs, _ip|
      attempts += 1
      raise Resolv::ResolvError if attempts < 3

      fixture.fetch(:record).content
    end

    task.check_reverse_records

    expect(attempts).to eq(3)
  end

  it 'reports DNS errors and exits non-zero when PTR cannot be resolved' do
    create_reverse_fixture!
    allow(task).to receive(:sleep)
    stub_ptr_query { |_addrs, _ip| raise Resolv::ResolvError }

    out, = capture_streams do
      expect { task.check_reverse_records }.to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
    end
    expect(out).to include("1 dns errors\n")
  end

  it 'reports incorrect PTR answers and exits non-zero' do
    create_reverse_fixture!
    stub_ptr_query { |_addrs, _ip| 'other.example.test.' }

    out, err = capture_streams do
      expect { task.check_reverse_records }.to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
    end
    expect(out).to include("1 records incorrect\n")
    expect(err).to include('returned "other.example.test."')
  end

  it 'filters DNS servers by SERVERS environment variable' do
    fixture = create_reverse_fixture!(server_count: 2)
    selected = fixture.fetch(:servers).last
    opened = []
    stub_ptr_query do |addrs, _ip|
      opened << addrs
      fixture.fetch(:record).content
    end

    with_env('SERVERS' => selected.name) { task.check_reverse_records }

    expect(opened).to eq([[selected.ipv4_addr]])
  end

  it 'prunes only old DNS transfer logs and keeps latest status fields' do
    stub_const("#{described_class}::DAYS", 1)
    zone = create_dns_zone!(user: SpecSeed.user, source: :external_source)
    server = create_dns_server!(node: SpecSeed.node)
    server_zone = create_dns_server_zone!(
      dns_zone: zone,
      dns_server: server,
      zone_type: :secondary_type
    )
    old = DnsServerZoneTransferLog.create!(
      dns_server_zone: server_zone,
      event_key: SecureRandom.hex(32),
      event_at: 2.days.ago,
      status: :failed,
      attempt_kind: :transfer,
      failure_class: :primary,
      reason_code: 'refused'
    )
    recent = DnsServerZoneTransferLog.create!(
      dns_server_zone: server_zone,
      event_key: SecureRandom.hex(32),
      event_at: 12.hours.ago,
      status: :success,
      attempt_kind: :transfer
    )
    server_zone.update!(
      last_transfer_log: old,
      last_transfer_at: old.event_at,
      last_transfer_status: old.status,
      last_transfer_reason_code: old.reason_code,
      last_transfer_reason: 'The primary DNS server refused the transfer'
    )

    expect { task.prune_transfer_logs }.to output("Deleted 1 DNS transfer logs\n").to_stdout

    expect(DnsServerZoneTransferLog.find_by(id: old.id)).to be_nil
    expect(DnsServerZoneTransferLog.find_by(id: recent.id)).to be_present
    expect(server_zone.reload.last_transfer_log_id).to be_nil
    expect(server_zone.last_transfer_status).to eq('failed')
    expect(server_zone.last_transfer_reason_code).to eq('refused')
  end

  it 'starts a fresh generation and deletes all prior transfer history' do
    enabled_external = create_dns_zone!(user: SpecSeed.user, source: :external_source)
    disabled_external = create_dns_zone!(user: SpecSeed.user, source: :external_source)
    internal = create_dns_zone!(user: SpecSeed.user, source: :internal_source)
    prior_epoch = 2.days.ago
    enabled_external.update_column(:primary_transfer_tracking_started_at, nil)
    disabled_external.update_columns(
      enabled: false,
      primary_transfer_tracking_started_at: prior_epoch
    )
    internal.update_column(:primary_transfer_tracking_started_at, prior_epoch)

    server_zone = create_dns_server_zone!(
      dns_zone: enabled_external,
      dns_server: create_dns_server!(node: SpecSeed.node),
      zone_type: :secondary_type
    )
    network = create_private_network!(split_prefix: 24)
    ip_address = create_ipv4_address_in_network!(
      network:,
      location: SpecSeed.location,
      user: SpecSeed.user
    )
    primary_ip = ip_address.ip_addr.split('.').map(&:to_i)
    primary_ip[-1] += 1
    host_ip_address = HostIpAddress.create!(
      ip_address:,
      ip_addr: primary_ip.join('.'),
      user_created: true
    )
    transfer = DnsZoneTransfer.create!(
      dns_zone: enabled_external,
      host_ip_address:,
      peer_type: :primary_type,
      confirmed: DnsZoneTransfer.confirmed(:confirmed)
    )
    DnsServerZonePrimaryTransferState.create!(
      dns_server_zone: server_zone,
      dns_zone_transfer: transfer,
      configuration_generation: server_zone.primary_transfer_configuration_generation,
      last_event_key: SecureRandom.hex(32),
      status: :unknown,
      last_attempt_at: prior_epoch,
      last_attempt_kind: :ixfr_probe
    )
    notify_log = DnsServerZoneTransferLog.create!(
      dns_server_zone: server_zone,
      dns_zone_transfer: transfer,
      event_key: SecureRandom.hex(32),
      event_at: prior_epoch + 1.hour,
      status: :success,
      attempt_kind: :notify,
      raw_message: 'zone example.test/IN: notify from 192.0.2.1#53: zone is up to date'
    )
    completed_log = DnsServerZoneTransferLog.create!(
      dns_server_zone: server_zone,
      event_key: SecureRandom.hex(32),
      event_at: prior_epoch + 2.hours,
      status: :success,
      attempt_kind: :transfer,
      raw_message: 'transfer of example.test: Transfer completed: 1 messages'
    )
    server_zone.update!(
      last_transfer_log: completed_log,
      last_transfer_at: completed_log.event_at,
      last_transfer_status: completed_log.status
    )

    allow(TransactionChains::DnsServerZone::RefreshConfiguration).to receive(:fire)
    expect { task.reset_primary_transfer_tracking }
      .to output(/Deleted 2 DNS transfer logs.*Queued 1 DNS server-zone configuration refreshes/m).to_stdout
    expect(TransactionChains::DnsServerZone::RefreshConfiguration)
      .to have_received(:fire)
      .with(server_zone)

    expect(DnsServerZonePrimaryTransferState.count).to eq(0)
    expect(DnsServerZoneTransferLog.find_by(id: completed_log.id)).to be_nil
    expect(DnsServerZoneTransferLog.find_by(id: notify_log.id)).to be_nil
    expect(server_zone.reload.last_transfer_log_id).to be_nil
    expect(enabled_external.reload.primary_transfer_tracking_started_at).to be_present
    expect(enabled_external.primary_transfer_tracking_started_at).to be > prior_epoch
    expect(enabled_external.primary_transfer_generation).to be_present
    expect(disabled_external.reload.primary_transfer_tracking_started_at).to be_nil
    expect(disabled_external.primary_transfer_generation).to be_nil
    expect(internal.reload.primary_transfer_tracking_started_at).to be_nil
    expect(internal.primary_transfer_generation).to be_nil
  end

  it 'can reset tracking without queuing configuration for an old nodectld' do
    allow(TransactionChains::DnsServerZone::RefreshConfiguration).to receive(:fire)
    original = ENV.fetch('REFRESH_CONFIGURATION', nil)
    ENV['REFRESH_CONFIGURATION'] = '0'

    expect { task.reset_primary_transfer_tracking }
      .to output(/Skipped DNS server-zone configuration refreshes/).to_stdout

    expect(TransactionChains::DnsServerZone::RefreshConfiguration)
      .not_to have_received(:fire)
  ensure
    if original.nil?
      ENV.delete('REFRESH_CONFIGURATION')
    else
      ENV['REFRESH_CONFIGURATION'] = original
    end
  end

  it 'blocks rollback until new-format DNS configuration updates are consumed' do
    chain = TransactionChain.create!(
      name: 'dns_probe_spec',
      type: 'TransactionChain',
      state: :queued,
      size: 1,
      progress: 0,
      user: User.current || SpecSeed.admin,
      user_session: UserSession.current,
      urgent_rollback: false
    )
    transaction = Transaction.create!(
      transaction_chain: chain,
      user: User.current || SpecSeed.admin,
      node: SpecSeed.node,
      handle: Transactions::DnsServerZone::Create.t_type,
      queue: 'dns',
      done: :waiting,
      reversible: :is_reversible,
      status: 0,
      input: '{"primary_transfer_generation":"generation"}'
    )

    expect { task.verify_primary_transfer_configuration_drained }
      .to raise_error(RuntimeError, /1 new-format DNS server-zone configuration transaction/)

    transaction.update!(done: :done)
    expect { task.verify_primary_transfer_configuration_drained }
      .to raise_error(RuntimeError, /1 new-format DNS server-zone configuration transaction/)

    chain.update!(state: :done)
    expect { task.verify_primary_transfer_configuration_drained }
      .to output(/No new-format DNS server-zone configuration transactions are pending/).to_stdout

    failed_chain = chain.dup
    failed_chain.state = :failed
    failed_chain.save!
    waiting_transaction = transaction.dup
    waiting_transaction.transaction_chain = failed_chain
    waiting_transaction.done = :waiting
    waiting_transaction.save!

    expect { task.verify_primary_transfer_configuration_drained }
      .to raise_error(RuntimeError, /1 new-format DNS server-zone configuration transaction/)

    waiting_transaction.update!(done: :done)
    expect { task.verify_primary_transfer_configuration_drained }
      .to output(/No new-format DNS server-zone configuration transactions are pending/).to_stdout
  end

  it 'blocks a protocol cutover until every old DNS configuration chain is drained' do
    chain = TransactionChain.create!(
      name: 'old_dns_spec',
      type: 'TransactionChain',
      state: :failed,
      size: 1,
      progress: 0,
      user: User.current || SpecSeed.admin,
      user_session: UserSession.current,
      urgent_rollback: false
    )
    transaction = Transaction.create!(
      transaction_chain: chain,
      user: User.current || SpecSeed.admin,
      node: SpecSeed.node,
      handle: Transactions::DnsServerZone::Create.t_type,
      queue: 'dns',
      done: :waiting,
      reversible: :is_reversible,
      status: 0,
      input: '{"name":"old-format.example.test"}'
    )

    expect { task.verify_configuration_drained }
      .to raise_error(RuntimeError, /1 DNS configuration transaction chain/)

    transaction.update!(done: :done)
    expect { task.verify_configuration_drained }
      .to output(/No DNS configuration transaction chains are pending/).to_stdout
  end
end
