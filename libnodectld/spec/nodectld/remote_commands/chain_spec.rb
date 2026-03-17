# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/confirmations'
require 'nodectld/remote_control'
require 'nodectld/remote_commands/base'
require 'nodectld/remote_commands/chain'
require 'bigdecimal'

RSpec.describe NodeCtld::RemoteCommands::Chain do
  def with_db_stub
    allow(NodeCtld::Db).to receive(:new).and_return(shared_db)
    yield
  end

  def decimal_value(row_id)
    BigDecimal(sql_value('SELECT value FROM cluster_resource_uses WHERE id = ?', row_id).to_s)
  end

  it 'returns grouped confirmation metadata by transaction id' do
    row1 = insert_cluster_resource_use(value: 10)
    row2 = insert_cluster_resource_use(value: 20)
    chain_id = insert_chain(size: 2)
    tx1 = insert_transaction(
      transaction_chain_id: chain_id,
      handle: NodeCtldSpec::TestHandles::OK
    )
    tx2 = insert_transaction(
      transaction_chain_id: chain_id,
      handle: NodeCtldSpec::TestHandles::OK,
      depends_on_id: tx1
    )
    insert_confirmation(
      transaction_id: tx1,
      class_name: 'ClusterResourceUse',
      table_name: 'cluster_resource_uses',
      row_pks: { 'id' => row1 },
      confirm_type: 0
    )
    insert_confirmation(
      transaction_id: tx2,
      class_name: 'ClusterResourceUse',
      table_name: 'cluster_resource_uses',
      row_pks: { 'id' => row2 },
      attr_changes: { 'value' => 2 },
      confirm_type: 7
    )

    cmd = described_class.new({ command: 'confirmations', chain: chain_id }, nil)
    ret = with_db_stub { cmd.exec }
    tx1_confirmations = ret[:output][:transactions].fetch(tx1)
    tx2_confirmations = ret[:output][:transactions].fetch(tx2)

    expect(ret[:ret]).to eq(:ok)
    expect(tx1_confirmations.length).to eq(1)
    expect(tx1_confirmations.first).to include(
      class_name: 'ClusterResourceUse',
      row_pks: { 'id' => row1 },
      attr_changes: nil,
      type: :create,
      done: false
    )
    expect(tx1_confirmations.first.fetch(:id).is_a?(Integer)).to be(true)
    expect(tx2_confirmations.length).to eq(1)
    expect(tx2_confirmations.first).to include(
      class_name: 'ClusterResourceUse',
      row_pks: { 'id' => row2 },
      attr_changes: { 'value' => 2 },
      type: :increment,
      done: false
    )
    expect(tx2_confirmations.first.fetch(:id).is_a?(Integer)).to be(true)
  end

  it 'confirms only the explicitly selected transactions' do
    row1 = insert_cluster_resource_use(value: 10, confirmed: 0)
    row2 = insert_cluster_resource_use(value: 20, confirmed: 0)
    chain_id = insert_chain(size: 2)
    tx1 = insert_transaction(transaction_chain_id: chain_id, handle: NodeCtldSpec::TestHandles::OK)
    tx2 = insert_transaction(
      transaction_chain_id: chain_id,
      handle: NodeCtldSpec::TestHandles::OK,
      depends_on_id: tx1
    )
    insert_confirmation(
      transaction_id: tx1,
      class_name: 'ClusterResourceUse',
      table_name: 'cluster_resource_uses',
      row_pks: { 'id' => row1 },
      confirm_type: 0
    )
    insert_confirmation(
      transaction_id: tx2,
      class_name: 'ClusterResourceUse',
      table_name: 'cluster_resource_uses',
      row_pks: { 'id' => row2 },
      confirm_type: 0
    )

    cmd = described_class.new(
      {
        command: 'confirm',
        chain: chain_id,
        transactions: [tx1],
        direction: 'execute',
        success: true
      },
      nil
    )
    ret = with_db_stub { cmd.exec }

    expect(ret[:ret]).to eq(:ok)
    expect(ret[:output][:transactions].keys).to eq([tx1])
    expect(sql_value('SELECT confirmed FROM cluster_resource_uses WHERE id = ?', row1)).to eq(1)
    expect(sql_value('SELECT confirmed FROM cluster_resource_uses WHERE id = ?', row2)).to eq(0)
    expect(sql_value('SELECT done FROM transaction_confirmations WHERE transaction_id = ?', tx1)).to eq(1)
    expect(sql_value('SELECT done FROM transaction_confirmations WHERE transaction_id = ?', tx2)).to eq(0)
  end

  it 'auto-selects all chain transactions when confirming without an explicit list' do
    row1 = insert_cluster_resource_use(value: 10, confirmed: 0)
    row2 = insert_cluster_resource_use(value: 20)
    chain_id = insert_chain(size: 2)
    tx1 = insert_transaction(transaction_chain_id: chain_id, handle: NodeCtldSpec::TestHandles::OK)
    tx2 = insert_transaction(
      transaction_chain_id: chain_id,
      handle: NodeCtldSpec::TestHandles::OK,
      depends_on_id: tx1
    )
    insert_confirmation(
      transaction_id: tx1,
      class_name: 'ClusterResourceUse',
      table_name: 'cluster_resource_uses',
      row_pks: { 'id' => row1 },
      confirm_type: 0
    )
    insert_confirmation(
      transaction_id: tx2,
      class_name: 'ClusterResourceUse',
      table_name: 'cluster_resource_uses',
      row_pks: { 'id' => row2 },
      attr_changes: { 'value' => 5 },
      confirm_type: 7
    )

    cmd = described_class.new(
      {
        command: 'confirm',
        chain: chain_id,
        direction: 'execute',
        success: true
      },
      nil
    )
    with_db_stub { cmd.exec }

    expect(sql_value('SELECT confirmed FROM cluster_resource_uses WHERE id = ?', row1)).to eq(1)
    expect(decimal_value(row2)).to eq(BigDecimal('25'))
    expect(sql_value('SELECT done FROM transaction_confirmations WHERE transaction_id = ?', tx1)).to eq(1)
    expect(sql_value('SELECT done FROM transaction_confirmations WHERE transaction_id = ?', tx2)).to eq(1)
  end

  it 'releases only locks when requested' do
    chain_id = insert_chain
    lock_id = insert_resource_lock(chain_id: chain_id, resource: 'SpecTxLock')
    lock_row_id = sql_value('SELECT row_id FROM resource_locks WHERE id = ?', lock_id)

    cmd = described_class.new(
      { command: 'release', chain: chain_id, release: ['locks'] },
      nil
    )
    ret = with_db_stub { cmd.exec }

    expect(ret[:ret]).to eq(:ok)
    expect(ret[:output][:locks].length).to eq(1)
    expect(ret[:output][:locks].first).to include(
      resource: 'SpecTxLock',
      row_id: lock_row_id
    )
    expect(
      sql_value(
        'SELECT COUNT(*) FROM resource_locks WHERE locked_by_type = ' \
        '\'TransactionChain\' AND locked_by_id = ?',
        chain_id
      )
    ).to eq(0)
  end

  it 'releases only ports when requested' do
    chain_id = insert_chain
    port_id = insert_port_reservation(chain_id: chain_id)

    cmd = described_class.new(
      { command: 'release', chain: chain_id, release: ['ports'] },
      nil
    )
    ret = with_db_stub { cmd.exec }

    expect(ret[:ret]).to eq(:ok)
    expect(ret[:output][:ports].length).to eq(1)
    expect(ret[:output][:ports].first).to include(
      node_name: 'spec-node-a',
      node_id: NodeCtldSpec::BaselineSeed.ids.fetch(:node_id),
      location_domain: 'loc.spec.test'
    )
    expect(
      sql_row(
        'SELECT transaction_chain_id, addr FROM port_reservations WHERE id = ?',
        port_id
      )
    ).to eq(
      'transaction_chain_id' => nil,
      'addr' => nil
    )
  end

  it 'releases both locks and ports together' do
    chain_id = insert_chain
    insert_resource_lock(chain_id: chain_id, resource: 'SpecTxLock')
    insert_port_reservation(chain_id: chain_id)

    cmd = described_class.new(
      { command: 'release', chain: chain_id, release: %w[locks ports] },
      nil
    )
    ret = with_db_stub { cmd.exec }

    expect(ret[:ret]).to eq(:ok)
    expect(ret[:output][:locks].length).to eq(1)
    expect(ret[:output][:ports].length).to eq(1)
  end

  it 'marks chains as resolved' do
    chain_id = insert_chain(state: NodeCtldSpec::TxState::CHAIN_FAILED)

    cmd = described_class.new({ command: 'resolve', chain: chain_id }, nil)
    ret = with_db_stub { cmd.exec }

    expect(ret[:ret]).to eq(:ok)
    expect(sql_value('SELECT state FROM transaction_chains WHERE id = ?', chain_id)).to eq(
      NodeCtldSpec::TxState::CHAIN_RESOLVED
    )
  end

  it 'retries a full chain' do
    chain_id = insert_chain(
      state: NodeCtldSpec::TxState::CHAIN_FAILED,
      size: 2,
      progress: 2
    )
    tx1 = insert_transaction(
      transaction_chain_id: chain_id,
      handle: NodeCtldSpec::TestHandles::OK,
      done: NodeCtldSpec::TxState::TX_DONE_DONE,
      status: NodeCtldSpec::TxState::TX_STATUS_OK
    )
    tx2 = insert_transaction(
      transaction_chain_id: chain_id,
      handle: NodeCtldSpec::TestHandles::OK,
      depends_on_id: tx1,
      done: NodeCtldSpec::TxState::TX_DONE_DONE,
      status: NodeCtldSpec::TxState::TX_STATUS_FAILED
    )

    cmd = described_class.new({ command: 'retry', chain: chain_id }, nil)
    ret = with_db_stub { cmd.exec }

    expect(ret[:ret]).to eq(:ok)
    expect(sql_value('SELECT done FROM transactions WHERE id = ?', tx1)).to eq(0)
    expect(sql_value('SELECT done FROM transactions WHERE id = ?', tx2)).to eq(0)
    expect(sql_value('SELECT state FROM transaction_chains WHERE id = ?', chain_id)).to eq(
      NodeCtldSpec::TxState::CHAIN_QUEUED
    )
    expect(sql_value('SELECT progress FROM transaction_chains WHERE id = ?', chain_id)).to eq(0)
  end

  it 'reopens the chain and resets transactions from the requested point' do
    chain_id = insert_chain(
      state: NodeCtldSpec::TxState::CHAIN_FAILED,
      size: 3,
      progress: 1
    )
    tx1 = insert_transaction(
      transaction_chain_id: chain_id,
      handle: NodeCtldSpec::TestHandles::OK,
      done: NodeCtldSpec::TxState::TX_DONE_DONE,
      status: NodeCtldSpec::TxState::TX_STATUS_OK
    )
    tx2 = insert_transaction(
      transaction_chain_id: chain_id,
      handle: NodeCtldSpec::TestHandles::OK,
      depends_on_id: tx1,
      done: NodeCtldSpec::TxState::TX_DONE_DONE,
      status: NodeCtldSpec::TxState::TX_STATUS_FAILED
    )
    tx3 = insert_transaction(
      transaction_chain_id: chain_id,
      handle: NodeCtldSpec::TestHandles::OK,
      depends_on_id: tx2,
      done: NodeCtldSpec::TxState::TX_DONE_DONE,
      status: NodeCtldSpec::TxState::TX_STATUS_FAILED
    )

    cmd = described_class.new(
      { command: 'retry', chain: chain_id, transactions: [tx2] },
      nil
    )
    ret = with_db_stub { cmd.exec }

    expect(ret[:ret]).to eq(:ok)
    expect(sql_value('SELECT state FROM transaction_chains WHERE id = ?', chain_id)).to eq(
      NodeCtldSpec::TxState::CHAIN_QUEUED
    )
    expect(sql_value('SELECT progress FROM transaction_chains WHERE id = ?', chain_id)).to eq(1)
    expect(sql_value('SELECT done FROM transactions WHERE id = ?', tx1)).to eq(1)
    expect(sql_value('SELECT done FROM transactions WHERE id = ?', tx2)).to eq(0)
    expect(sql_value('SELECT done FROM transactions WHERE id = ?', tx3)).to eq(0)
  end

  it 'raises on invalid retry transaction ids' do
    chain_id = insert_chain(state: NodeCtldSpec::TxState::CHAIN_FAILED)

    cmd = described_class.new(
      { command: 'retry', chain: chain_id, transactions: [999_999] },
      nil
    )

    expect do
      with_db_stub { cmd.exec }
    end.to raise_error(
      NodeCtld::RemoteCommandError,
      /Transaction 999999 not found in chain #{chain_id}/
    )
  end
end
