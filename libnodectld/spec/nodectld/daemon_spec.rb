# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/command'
require 'nodectld/daemon'

RSpec.describe NodeCtld::Daemon do
  let(:daemon) do
    described_class.allocate.tap do |d|
      d.instance_variable_set(
        :@queues,
        instance_double(NodeCtld::Queues, total_limit: 50)
      )
      d.instance_variable_set(:@cmd_counter, 0)
    end
  end

  after do
    daemon.resume
  end

  def selected_ids(limit = nil)
    ids = []

    daemon.select_commands(shared_db, limit).each do |row|
      ids << row['id'].to_i
    end

    ids
  end

  def insert_node(name:, ip_addr:)
    sql_insert('nodes', {
      name: name,
      location_id: NodeCtldSpec::BaselineSeed.ids.fetch(:location_id),
      ip_addr: ip_addr,
      max_vps: 10,
      max_tx: 235_929_600,
      max_rx: 235_929_600,
      maintenance_lock: 0,
      cpus: 4,
      total_memory: 4096,
      total_swap: 1024,
      role: 0,
      hypervisor_type: 1,
      active: 1
    })
  end

  it 'selects root queued transactions for the current node' do
    chain_id = insert_chain(state: NodeCtldSpec::TxState::CHAIN_QUEUED)
    tx_id = insert_transaction(
      transaction_chain_id: chain_id,
      handle: NodeCtldSpec::TestHandles::OK
    )

    expect(selected_ids).to include(tx_id)
  end

  it 'selects dependency-satisfied follower transactions' do
    chain_a = insert_chain(state: NodeCtldSpec::TxState::CHAIN_QUEUED, size: 2, progress: 0)
    root_a = insert_transaction(
      transaction_chain_id: chain_a,
      handle: NodeCtldSpec::TestHandles::OK,
      priority: 5
    )
    follower_a = insert_transaction(
      transaction_chain_id: chain_a,
      handle: NodeCtldSpec::TestHandles::OK,
      depends_on_id: root_a,
      priority: 5
    )
    chain_b = insert_chain(state: NodeCtldSpec::TxState::CHAIN_QUEUED, size: 2, progress: 1)
    root_b = insert_transaction(
      transaction_chain_id: chain_b,
      handle: NodeCtldSpec::TestHandles::OK,
      priority: 10,
      done: NodeCtldSpec::TxState::TX_DONE_DONE,
      status: NodeCtldSpec::TxState::TX_STATUS_OK
    )
    follower_b = insert_transaction(
      transaction_chain_id: chain_b,
      handle: NodeCtldSpec::TestHandles::OK,
      depends_on_id: root_b,
      priority: 10
    )

    ids = selected_ids

    expect(ids).to include(root_a, follower_b)
    expect(ids).not_to include(follower_a, root_b)
  end

  it 'does not select waiting followers when their predecessor is still waiting' do
    chain_id = insert_chain(state: NodeCtldSpec::TxState::CHAIN_QUEUED, size: 2, progress: 0)
    root_id = insert_transaction(
      transaction_chain_id: chain_id,
      handle: NodeCtldSpec::TestHandles::OK
    )
    follower_id = insert_transaction(
      transaction_chain_id: chain_id,
      handle: NodeCtldSpec::TestHandles::OK,
      depends_on_id: root_id
    )

    ids = selected_ids

    expect(ids).to include(root_id)
    expect(ids).not_to include(follower_id)
  end

  it 'orders selected execute transactions by priority descending' do
    high_chain = insert_chain(state: NodeCtldSpec::TxState::CHAIN_QUEUED)
    low_chain = insert_chain(state: NodeCtldSpec::TxState::CHAIN_QUEUED)
    low_tx = insert_transaction(
      transaction_chain_id: low_chain,
      handle: NodeCtldSpec::TestHandles::OK,
      priority: 1
    )
    high_tx = insert_transaction(
      transaction_chain_id: high_chain,
      handle: NodeCtldSpec::TestHandles::OK,
      priority: 10
    )

    expect(selected_ids.first(2)).to eq([high_tx, low_tx])
  end

  it 'filters selection by the configured current node id' do
    other_node_id = insert_node(name: 'spec-node-b', ip_addr: '192.0.2.102')
    local_chain = insert_chain(state: NodeCtldSpec::TxState::CHAIN_QUEUED)
    other_chain = insert_chain(state: NodeCtldSpec::TxState::CHAIN_QUEUED)
    local_tx = insert_transaction(
      transaction_chain_id: local_chain,
      handle: NodeCtldSpec::TestHandles::OK
    )
    other_tx = insert_transaction(
      transaction_chain_id: other_chain,
      handle: NodeCtldSpec::TestHandles::OK,
      node_id: other_node_id
    )

    ids = selected_ids

    expect(ids).to include(local_tx)
    expect(ids).not_to include(other_tx)
  end

  it 'returns rollback predecessor rows in reverse order' do
    chain_a = insert_chain(state: NodeCtldSpec::TxState::CHAIN_ROLLBACKING, size: 2, progress: 0)
    rollback_a1 = insert_transaction(
      transaction_chain_id: chain_a,
      handle: NodeCtldSpec::TestHandles::OK,
      done: NodeCtldSpec::TxState::TX_DONE_DONE,
      status: NodeCtldSpec::TxState::TX_STATUS_OK
    )
    insert_transaction(
      transaction_chain_id: chain_a,
      handle: NodeCtldSpec::TestHandles::OK,
      depends_on_id: rollback_a1,
      done: NodeCtldSpec::TxState::TX_DONE_ROLLED_BACK,
      status: NodeCtldSpec::TxState::TX_STATUS_OK
    )

    chain_b = insert_chain(state: NodeCtldSpec::TxState::CHAIN_ROLLBACKING, size: 2, progress: 0)
    rollback_b1 = insert_transaction(
      transaction_chain_id: chain_b,
      handle: NodeCtldSpec::TestHandles::OK,
      done: NodeCtldSpec::TxState::TX_DONE_DONE,
      status: NodeCtldSpec::TxState::TX_STATUS_OK
    )
    insert_transaction(
      transaction_chain_id: chain_b,
      handle: NodeCtldSpec::TestHandles::OK,
      depends_on_id: rollback_b1,
      done: NodeCtldSpec::TxState::TX_DONE_ROLLED_BACK,
      status: NodeCtldSpec::TxState::TX_STATUS_OK
    )

    expect(selected_ids).to eq([rollback_b1, rollback_a1])
  end

  it 'respects the selection limit' do
    ids = 3.times.map do
      chain_id = insert_chain(state: NodeCtldSpec::TxState::CHAIN_QUEUED)
      insert_transaction(
        transaction_chain_id: chain_id,
        handle: NodeCtldSpec::TestHandles::OK
      )
    end

    expect(selected_ids(2)).to eq(ids.first(2))
  end

  it 'stops enqueuing selected commands after the daemon is paused' do
    rows = [
      { 'queue' => 'vps' },
      { 'queue' => 'vps' }
    ]
    cmd1 = instance_double(NodeCtld::Command)
    cmd2 = instance_double(NodeCtld::Command)

    daemon.resume
    allow(daemon).to receive_messages(check_commands?: true, select_commands: rows)
    allow(NodeCtld::Command).to receive(:new).and_return(cmd1, cmd2)
    allow(daemon).to receive(:do_command) do
      daemon.pause(true)
    end

    daemon.do_commands(shared_db)

    expect(daemon).to have_received(:do_command).with(cmd1)
    expect(daemon).not_to have_received(:do_command).with(cmd2)
    expect(NodeCtld::Command).to have_received(:new).once
  end

  %i[load setup request close].each do |stage|
    it "polls and dispatches execute and rollback commands while monitor #{stage} is blocked" do
      queued_chain = insert_chain(state: NodeCtldSpec::TxState::CHAIN_QUEUED)
      execute_id = insert_transaction(transaction_chain_id: queued_chain, handle: NodeCtldSpec::TestHandles::OK)
      rollback_chain = insert_chain(state: NodeCtldSpec::TxState::CHAIN_ROLLBACKING, size: 2)
      rollback_id = insert_transaction(
        transaction_chain_id: rollback_chain, handle: NodeCtldSpec::TestHandles::OK,
        done: NodeCtldSpec::TxState::TX_DONE_DONE, status: NodeCtldSpec::TxState::TX_STATUS_OK
      )
      insert_transaction(
        transaction_chain_id: rollback_chain, handle: NodeCtldSpec::TestHandles::OK,
        depends_on_id: rollback_id, done: NodeCtldSpec::TxState::TX_DONE_ROLLED_BACK,
        status: NodeCtldSpec::TxState::TX_STATUS_OK
      )
      directory = Dir.mktmpdir('async-boot-daemon-spec-')
      path = File.join(directory, 'ledger.json')
      File.write(path, JSON.generate(
                         schema_version: 1, boot_id: 'current', phase: 'enrolling',
                         capture_deadline_boottime_seconds: 300, failure_reason: nil,
                         captured_at_boottime_seconds: nil, obligations: []
                       ))
      entered = Queue.new
      release = Queue.new
      barrier = lambda {
        entered << true
        release.pop
      }
      rpc = instance_double(NodeCtld::RpcClient, list_vps_boot_autostart: { 'schema_version' => 1, 'vpses' => [] }, close: nil)
      allow(NodeCtld::RpcClient).to receive(:new).and_return(rpc)
      factory = lambda do
        barrier.call if stage == :load
        NodeCtld::VpsBootAutostartLedger.new(path:, marker: File.join(directory, 'marker'), boot_id: 'current')
      end
      case stage
      when :setup
        allow(NodeCtld::RpcClient).to receive(:new) {
          barrier.call
          rpc
        }
      when :request
        allow(rpc).to receive(:list_vps_boot_autostart) {
          barrier.call
          { 'schema_version' => 1, 'vpses' => [] }
        }
      when :close
        allow(rpc).to receive(:close) { barrier.call }
      end
      monitor = NodeCtld::VpsBootAutostart.new(ledger_factory: factory, clock: -> { 20 })
      daemon.instance_variable_set(:@vps_boot_autostart, monitor)
      allow(daemon).to receive(:check_commands?).and_return(true)
      allow(daemon).to receive(:do_command)
      daemon.resume
      worker = Thread.new { monitor.update }
      expect(entered.pop(timeout: 2)).to be(true)
      transactions = Thread.new { daemon.do_commands(shared_db) }
      expect(transactions.join(1)).not_to be_nil
      expect(daemon).to have_received(:check_commands?).with(shared_db)
      expect(daemon).to have_received(:do_command).with(have_attributes(id: execute_id))
      expect(daemon).to have_received(:do_command).with(have_attributes(id: rollback_id))
      scraper = Thread.new { monitor.snapshot }
      expect(scraper.join(1)).not_to be_nil
      expect(scraper.value.reason).to eq(stage == :load ? 'state_loading' : 'none')
      expect(worker.alive?).to be(true)
      release << true
      expect(worker.join(2)).not_to be_nil
    ensure
      release << true if worker&.alive?
      worker&.join(2)
      transactions&.join(2)
      scraper&.join(2)
      FileUtils.remove_entry(directory) if directory
    end
  end

  [['enrolling', 5], ['active', 120], ['unavailable', 120]].each do |state, interval|
    it "uses the published #{state} snapshot to select monitoring cadence" do
      monitor = instance_double(NodeCtld::VpsBootAutostart, update: nil, snapshot: instance_double(NodeCtld::VpsBootAutostart::Snapshot, state:))
      daemon.instance_variable_set(:@vps_boot_autostart, monitor)
      $CFG.patch(vpsadmin: { vps_status_interval: 120 })
      allow(Process).to receive(:clock_gettime).with(Process::CLOCK_BOOTTIME).and_return(100, 102)
      allow(daemon).to receive(:run_thread_unless_runs) do |name, &block|
        block.call if name == :vps_boot_autostart
      end
      allow(daemon).to receive(:sleep) { throw :finished }
      catch(:finished) { daemon.run_threads }
      expect(daemon).to have_received(:sleep).with(interval - 2).once
      expect(monitor).to have_received(:update).once
      expect(monitor).to have_received(:snapshot).once
    end
  end

  it 'records a successful transaction metadata poll using both clocks' do
    result = double(get: { 'update_time' => Time.at(123) })
    allow(shared_db).to receive(:prepared).and_return(result)
    allow(Process).to receive(:clock_gettime)
      .with(Process::CLOCK_MONOTONIC)
      .and_return(456.5)

    expect(daemon.check_commands?(shared_db)).to be(true)
    expect(daemon.last_transaction_check).to be_a(Time)
    expect(daemon.last_transaction_check_monotonic).to eq(456.5)
  end

  it 'does not record a failed transaction metadata poll' do
    result = double(get: nil)
    allow(shared_db).to receive(:prepared).and_return(result)
    daemon.instance_variable_set(:@last_transaction_check, Time.at(123))
    daemon.instance_variable_set(:@last_transaction_check_monotonic, 456.5)

    expect do
      daemon.check_commands?(shared_db)
    end.to raise_error(NodeCtld::TransactionCheckError)
    expect(daemon.last_transaction_check).to eq(Time.at(123))
    expect(daemon.last_transaction_check_monotonic).to eq(456.5)
  end

  it 'skips execute commands while the chain is blocked' do
    cmd = instance_double(
      NodeCtld::Command,
      chain_id: 6,
      current_chain_direction: :execute,
      id: 19,
      worker_id: 6
    )
    queues = daemon.instance_variable_get(:@queues)

    allow(daemon).to receive(:chain_blocked?).with(6).and_return(true)
    allow(daemon).to receive(:log)
    allow(queues).to receive(:execute)

    daemon.send(:do_command, cmd)

    expect(queues).not_to have_received(:execute)
  end

  it 'allows rollback commands to run even when the chain is blocked' do
    cmd = instance_double(
      NodeCtld::Command,
      chain_id: 6,
      current_chain_direction: :rollback,
      id: 18,
      worker_id: 6
    )
    queues = daemon.instance_variable_get(:@queues)

    allow(daemon).to receive(:chain_blocked?).with(6).and_return(true)
    allow(daemon).to receive(:log)
    allow(queues).to receive(:execute).with(cmd).and_return(true)

    daemon.send(:do_command, cmd)

    expect(queues).to have_received(:execute).with(cmd)
    expect(daemon.instance_variable_get(:@cmd_counter)).to eq(1)
  end
end
