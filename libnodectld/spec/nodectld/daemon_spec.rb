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
