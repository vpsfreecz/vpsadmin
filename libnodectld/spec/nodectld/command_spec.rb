# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/transaction_verifier'
require 'nodectld/confirmations'
require 'nodectld/command'

RSpec.describe NodeCtld::Command do
  def build_command(tx_id)
    described_class.new(joined_transaction_row(tx_id))
  end

  def execute_and_save(tx_id)
    cmd = build_command(tx_id)
    cmd.execute
    cmd.save(shared_db)
    cmd
  end

  def tx_state(tx_id)
    row = sql_row('SELECT done, status FROM transactions WHERE id = ?', tx_id)

    {
      'done' => row.fetch('done').to_i,
      'status' => row.fetch('status').to_i
    }
  end

  def chain_state(chain_id)
    row = sql_row(
      'SELECT state, progress FROM transaction_chains WHERE id = ?',
      chain_id
    )

    {
      'state' => row.fetch('state').to_i,
      'progress' => row.fetch('progress').to_i
    }
  end

  it 'persists an unsupported handle error' do
    chain_id = insert_chain
    tx_id = insert_transaction(transaction_chain_id: chain_id, handle: 123_456)

    cmd = build_command(tx_id)
    expect(cmd.execute).to be(false)
    cmd.save(shared_db)

    expect(tx_state(tx_id)).to eq(
      'done' => NodeCtldSpec::TxState::TX_DONE_ROLLED_BACK,
      'status' => NodeCtldSpec::TxState::TX_STATUS_FAILED
    )
    expect(transaction_output(tx_id)).to include('error' => 'Unsupported command')
    expect(chain_state(chain_id)).to include(
      'state' => NodeCtldSpec::TxState::CHAIN_FAILED
    )
  end

  it 'persists a bad input syntax error' do
    chain_id = insert_chain
    tx_id = insert_transaction(
      transaction_chain_id: chain_id,
      handle: NodeCtldSpec::TestHandles::OK,
      input: '{'
    )

    cmd = build_command(tx_id)
    expect(cmd.execute).to be(false)
    cmd.save(shared_db)

    expect(tx_state(tx_id)).to eq(
      'done' => NodeCtldSpec::TxState::TX_DONE_ROLLED_BACK,
      'status' => NodeCtldSpec::TxState::TX_STATUS_FAILED
    )
    expect(transaction_output(tx_id)).to include('error' => 'Bad input syntax')
    expect(chain_state(chain_id)).to include(
      'state' => NodeCtldSpec::TxState::CHAIN_FAILED
    )
  end

  it 'fails transactions whose handler returns an invalid value' do
    chain_id = insert_chain
    tx_id = insert_transaction(
      transaction_chain_id: chain_id,
      handle: NodeCtldSpec::TestHandles::INVALID_RETURN,
      reversible: NodeCtldSpec::TxState::TX_NOT_REVERSIBLE
    )

    execute_and_save(tx_id)

    expect(tx_state(tx_id)).to eq(
      'done' => NodeCtldSpec::TxState::TX_DONE_DONE,
      'status' => NodeCtldSpec::TxState::TX_STATUS_FAILED
    )
    expect(transaction_output(tx_id)).to include(
      'cmd' => 'process handler return value',
      'exitstatus' => 1
    )
    expect(transaction_output(tx_id).fetch('error')).to include(
      'did not return expected value'
    )
    expect(chain_state(chain_id)).to include(
      'state' => NodeCtldSpec::TxState::CHAIN_FAILED
    )
  end

  it 'executes unsigned transactions without invoking the verifier' do
    chain_id = insert_chain
    tx_id = insert_transaction(
      transaction_chain_id: chain_id,
      handle: NodeCtldSpec::TestHandles::OK,
      signature: nil
    )

    allow(NodeCtld::TransactionVerifier).to receive(:verify_base64)

    execute_and_save(tx_id)

    expect(NodeCtld::TransactionVerifier).not_to have_received(:verify_base64)
    expect(sql_value('SELECT done FROM transactions WHERE id = ?', tx_id)).to eq(1)
    expect(sql_value('SELECT status FROM transactions WHERE id = ?', tx_id)).to eq(1)
  end

  it 'persists an invalid signature error' do
    chain_id = insert_chain
    payload, = NodeCtldSpec::SigningHelpers.signed_input(
      chain_id: chain_id,
      depends_on_id: nil,
      handle: NodeCtldSpec::TestHandles::OK,
      node_id: NodeCtldSpec::BaselineSeed.ids.fetch(:node_id),
      reversible: NodeCtldSpec::TxState::TX_REVERSIBLE,
      input: {}
    )
    tx_id = insert_transaction(
      transaction_chain_id: chain_id,
      handle: NodeCtldSpec::TestHandles::OK,
      input: payload,
      signature: NodeCtldSpec::SigningHelpers.sign_base64("#{payload}-tampered")
    )

    cmd = build_command(tx_id)
    expect(cmd.execute).to be(false)
    cmd.save(shared_db)

    expect(tx_state(tx_id)).to eq(
      'done' => NodeCtldSpec::TxState::TX_DONE_ROLLED_BACK,
      'status' => NodeCtldSpec::TxState::TX_STATUS_FAILED
    )
    expect(transaction_output(tx_id)).to include('error' => 'Invalid signature')
    expect(chain_state(chain_id)).to include(
      'state' => NodeCtldSpec::TxState::CHAIN_FAILED
    )
  end

  it 'rejects transactions whose signed options do not match relational columns' do
    chain_id = insert_chain
    payload, signature = NodeCtldSpec::SigningHelpers.signed_input(
      chain_id: chain_id,
      depends_on_id: nil,
      handle: NodeCtldSpec::TestHandles::OK,
      node_id: NodeCtldSpec::BaselineSeed.ids.fetch(:node_id),
      reversible: NodeCtldSpec::TxState::TX_REVERSIBLE,
      input: {}
    )

    tx_id = insert_transaction(
      transaction_chain_id: chain_id,
      handle: NodeCtldSpec::TestHandles::FAIL_EXEC,
      input: payload,
      signature: signature
    )

    cmd = build_command(tx_id)
    expect(cmd.execute).to be(false)
    cmd.save(shared_db)

    expect(tx_state(tx_id)).to eq(
      'done' => NodeCtldSpec::TxState::TX_DONE_ROLLED_BACK,
      'status' => NodeCtldSpec::TxState::TX_STATUS_FAILED
    )
    expect(transaction_output(tx_id)).to include(
      'error' => 'Signed options do not match relational options'
    )
    expect(chain_state(chain_id)).to include(
      'state' => NodeCtldSpec::TxState::CHAIN_FAILED
    )
  end

  it 'persists successful execution and closes a single-transaction chain' do
    chain_id = insert_chain
    tx_id = insert_transaction(
      transaction_chain_id: chain_id,
      handle: NodeCtldSpec::TestHandles::OK
    )

    execute_and_save(tx_id)

    expect(sql_value('SELECT done FROM transactions WHERE id = ?', tx_id)).to eq(1)
    expect(sql_value('SELECT status FROM transactions WHERE id = ?', tx_id)).to eq(1)
    expect(sql_value('SELECT progress FROM transaction_chains WHERE id = ?', chain_id)).to eq(1)
    expect(sql_value('SELECT state FROM transaction_chains WHERE id = ?', chain_id)).to eq(
      NodeCtldSpec::TxState::CHAIN_DONE
    )
  end

  it 'accepts valid signed transactions' do
    chain_id = insert_chain
    payload, signature = NodeCtldSpec::SigningHelpers.signed_input(
      chain_id: chain_id,
      depends_on_id: nil,
      handle: NodeCtldSpec::TestHandles::OK,
      node_id: NodeCtldSpec::BaselineSeed.ids.fetch(:node_id),
      reversible: NodeCtldSpec::TxState::TX_REVERSIBLE,
      input: {}
    )
    tx_id = insert_transaction(
      transaction_chain_id: chain_id,
      handle: NodeCtldSpec::TestHandles::OK,
      input: payload,
      signature: signature
    )

    execute_and_save(tx_id)

    expect(sql_value('SELECT status FROM transactions WHERE id = ?', tx_id)).to eq(1)
    expect(transaction_output(tx_id)).to include('handler' => 'ok')
  end

  it 'stores warning status and still treats the chain as successful' do
    chain_id = insert_chain
    tx_id = insert_transaction(
      transaction_chain_id: chain_id,
      handle: NodeCtldSpec::TestHandles::WARNING
    )

    execute_and_save(tx_id)

    expect(sql_value('SELECT status FROM transactions WHERE id = ?', tx_id)).to eq(2)
    expect(sql_value('SELECT state FROM transaction_chains WHERE id = ?', chain_id)).to eq(
      NodeCtldSpec::TxState::CHAIN_DONE
    )
  end

  it 'runs on_save and post_save only on successful execute save paths' do
    chain_id = insert_chain
    tx_id = insert_transaction(
      transaction_chain_id: chain_id,
      handle: NodeCtldSpec::TestHandles::HOOKS_PROBE
    )

    execute_and_save(tx_id)

    expect(Thread.current[:spec_on_save_calls]).to eq(1)
    expect(Thread.current[:spec_post_save_calls]).to eq(1)
  end

  it 'does not run on_save or post_save for failed paths' do
    chain_id = insert_chain
    tx_id = insert_transaction(
      transaction_chain_id: chain_id,
      handle: NodeCtldSpec::TestHandles::FAIL_EXEC,
      reversible: NodeCtldSpec::TxState::TX_NOT_REVERSIBLE
    )

    execute_and_save(tx_id)

    expect(Thread.current[:spec_on_save_calls]).to eq(0)
    expect(Thread.current[:spec_post_save_calls]).to eq(0)
  end

  it 'persists hard kills as failed transactions' do
    chain_id = insert_chain
    tx_id = insert_transaction(
      transaction_chain_id: chain_id,
      handle: NodeCtldSpec::TestHandles::OK,
      reversible: NodeCtldSpec::TxState::TX_NOT_REVERSIBLE
    )

    cmd = build_command(tx_id)
    handler = NodeCtldSpec::TestHandlers::Ok.new(cmd, {})

    cmd.instance_variable_set(:@cmd, handler)
    cmd.instance_variable_set(:@current_method, :exec)
    cmd.instance_variable_set(:@current_klass, NodeCtldSpec::TestHandlers::Ok.name)

    cmd.killed(true)
    cmd.save(shared_db)

    expect(transaction_output(tx_id)).to include('error' => 'Killed')
    expect(tx_state(tx_id)).to eq(
      'done' => NodeCtldSpec::TxState::TX_DONE_DONE,
      'status' => NodeCtldSpec::TxState::TX_STATUS_FAILED
    )
    expect(chain_state(chain_id)).to include(
      'state' => NodeCtldSpec::TxState::CHAIN_FAILED
    )
  end

  it 'rolls back reversible transactions after SystemCommandFailed in exec' do
    chain_id = insert_chain
    tx_id = insert_transaction(
      transaction_chain_id: chain_id,
      handle: NodeCtldSpec::TestHandles::FAIL_EXEC,
      reversible: NodeCtldSpec::TxState::TX_REVERSIBLE
    )

    execute_and_save(tx_id)

    expect(sql_value('SELECT done FROM transactions WHERE id = ?', tx_id)).to eq(2)
    expect(sql_value('SELECT status FROM transactions WHERE id = ?', tx_id)).to eq(1)
    expect(sql_value('SELECT state FROM transaction_chains WHERE id = ?', chain_id)).to eq(
      NodeCtldSpec::TxState::CHAIN_FAILED
    )
    expect(transaction_output(tx_id)).to include(
      'cmd' => 'spec-fail-exec',
      'exitstatus' => 23,
      'error' => 'exec failed',
      'rolled_back' => true
    )
  end

  it 'rolls back reversible transactions after generic exec exceptions' do
    chain_id = insert_chain
    tx_id = insert_transaction(
      transaction_chain_id: chain_id,
      handle: NodeCtldSpec::TestHandles::RAISE_GENERIC,
      reversible: NodeCtldSpec::TxState::TX_REVERSIBLE
    )

    execute_and_save(tx_id)

    expect(sql_value('SELECT done FROM transactions WHERE id = ?', tx_id)).to eq(2)
    expect(sql_value('SELECT status FROM transactions WHERE id = ?', tx_id)).to eq(1)
    expect(sql_value('SELECT state FROM transaction_chains WHERE id = ?', chain_id)).to eq(
      NodeCtldSpec::TxState::CHAIN_FAILED
    )
    expect(transaction_output(tx_id).fetch('error')).to include('generic failure from spec handler')
  end

  it 'persists command not implemented failures' do
    chain_id = insert_chain
    tx_id = insert_transaction(
      transaction_chain_id: chain_id,
      handle: NodeCtldSpec::TestHandles::NOT_IMPLEMENTED,
      reversible: NodeCtldSpec::TxState::TX_REVERSIBLE
    )

    execute_and_save(tx_id)

    expect(tx_state(tx_id)).to eq(
      'done' => NodeCtldSpec::TxState::TX_DONE_ROLLED_BACK,
      'status' => NodeCtldSpec::TxState::TX_STATUS_FAILED
    )
    expect(sql_value('SELECT state FROM transaction_chains WHERE id = ?', chain_id)).to eq(
      NodeCtldSpec::TxState::CHAIN_FAILED
    )
    expect(transaction_output(tx_id)).to include('error' => 'Command not implemented')
  end

  it 'marks unsupported reversible transactions as rolled back before chain rollback starts' do
    chain_id = insert_chain(size: 3, progress: 1)
    tx1 = insert_transaction(
      transaction_chain_id: chain_id,
      handle: NodeCtldSpec::TestHandles::OK,
      done: NodeCtldSpec::TxState::TX_DONE_DONE,
      status: NodeCtldSpec::TxState::TX_STATUS_OK
    )
    tx2 = insert_transaction(
      transaction_chain_id: chain_id,
      handle: 123_456,
      depends_on_id: tx1,
      reversible: NodeCtldSpec::TxState::TX_REVERSIBLE
    )
    tx3 = insert_transaction(
      transaction_chain_id: chain_id,
      handle: NodeCtldSpec::TestHandles::OK,
      depends_on_id: tx2,
      reversible: NodeCtldSpec::TxState::TX_REVERSIBLE
    )

    execute_and_save(tx2)

    expect(chain_state(chain_id)).to eq(
      'state' => NodeCtldSpec::TxState::CHAIN_ROLLBACKING,
      'progress' => 0
    )
    expect(tx_state(tx1)).to eq(
      'done' => NodeCtldSpec::TxState::TX_DONE_DONE,
      'status' => NodeCtldSpec::TxState::TX_STATUS_OK
    )
    expect(tx_state(tx2)).to eq(
      'done' => NodeCtldSpec::TxState::TX_DONE_ROLLED_BACK,
      'status' => NodeCtldSpec::TxState::TX_STATUS_FAILED
    )
    expect(tx_state(tx3)).to eq(
      'done' => NodeCtldSpec::TxState::TX_DONE_DONE,
      'status' => NodeCtldSpec::TxState::TX_STATUS_FAILED
    )
    expect(transaction_output(tx2)).to include('error' => 'Unsupported command')
    expect(transaction_output(tx3)).to eq('error' => 'Dependency failed')
  end

  it 'fails followers when a non-reversible transaction fails' do
    chain_id = insert_chain(size: 2, progress: 0)
    tx1 = insert_transaction(
      transaction_chain_id: chain_id,
      handle: NodeCtldSpec::TestHandles::FAIL_EXEC,
      reversible: NodeCtldSpec::TxState::TX_NOT_REVERSIBLE
    )
    tx2 = insert_transaction(
      transaction_chain_id: chain_id,
      handle: NodeCtldSpec::TestHandles::OK,
      depends_on_id: tx1
    )

    execute_and_save(tx1)

    expect(sql_value('SELECT done FROM transactions WHERE id = ?', tx1)).to eq(1)
    expect(sql_value('SELECT status FROM transactions WHERE id = ?', tx1)).to eq(0)
    expect(sql_value('SELECT done FROM transactions WHERE id = ?', tx2)).to eq(1)
    expect(sql_value('SELECT status FROM transactions WHERE id = ?', tx2)).to eq(0)
    expect(transaction_output(tx2)).to eq('error' => 'Dependency failed')
    expect(sql_value('SELECT state FROM transaction_chains WHERE id = ?', chain_id)).to eq(
      NodeCtldSpec::TxState::CHAIN_FAILED
    )
  end

  it 'rolls back earlier successful steps when a later reversible step fails' do
    chain_id = insert_chain(size: 3, progress: 0)
    confirmation_row_id = insert_cluster_resource_use(confirmed: 0)
    tx1 = insert_transaction(
      transaction_chain_id: chain_id,
      handle: NodeCtldSpec::TestHandles::OK,
      reversible: NodeCtldSpec::TxState::TX_REVERSIBLE
    )
    tx2 = insert_transaction(
      transaction_chain_id: chain_id,
      handle: NodeCtldSpec::TestHandles::FAIL_EXEC,
      depends_on_id: tx1,
      reversible: NodeCtldSpec::TxState::TX_REVERSIBLE
    )
    tx3 = insert_transaction(
      transaction_chain_id: chain_id,
      handle: NodeCtldSpec::TestHandles::OK,
      depends_on_id: tx2,
      reversible: NodeCtldSpec::TxState::TX_REVERSIBLE
    )
    insert_confirmation(
      transaction_id: tx1,
      class_name: 'ClusterResourceUse',
      table_name: 'cluster_resource_uses',
      row_pks: { 'id' => confirmation_row_id },
      confirm_type: 0
    )
    insert_resource_lock(chain_id: chain_id)
    port_id = insert_port_reservation(chain_id: chain_id)

    execute_and_save(tx1)

    expect(chain_state(chain_id)).to eq(
      'state' => NodeCtldSpec::TxState::CHAIN_QUEUED,
      'progress' => 1
    )
    expect(tx_state(tx1)).to eq(
      'done' => NodeCtldSpec::TxState::TX_DONE_DONE,
      'status' => NodeCtldSpec::TxState::TX_STATUS_OK
    )

    execute_and_save(tx2)

    expect(chain_state(chain_id)).to eq(
      'state' => NodeCtldSpec::TxState::CHAIN_ROLLBACKING,
      'progress' => 0
    )
    expect(tx_state(tx2)).to eq(
      'done' => NodeCtldSpec::TxState::TX_DONE_ROLLED_BACK,
      'status' => NodeCtldSpec::TxState::TX_STATUS_OK
    )
    expect(tx_state(tx3)).to eq(
      'done' => NodeCtldSpec::TxState::TX_DONE_DONE,
      'status' => NodeCtldSpec::TxState::TX_STATUS_FAILED
    )
    expect(transaction_output(tx2)).to include(
      'cmd' => 'spec-fail-exec',
      'exitstatus' => 23,
      'error' => 'exec failed',
      'rolled_back' => true
    )
    expect(transaction_output(tx3)).to eq('error' => 'Dependency failed')

    execute_and_save(tx1)

    expect(chain_state(chain_id)).to eq(
      'state' => NodeCtldSpec::TxState::CHAIN_FAILED,
      'progress' => 0
    )
    expect(tx_state(tx1)).to eq(
      'done' => NodeCtldSpec::TxState::TX_DONE_ROLLED_BACK,
      'status' => NodeCtldSpec::TxState::TX_STATUS_OK
    )
    expect(transaction_output(tx1)).to include('handler' => 'ok-rollback')
    expect(sql_value('SELECT COUNT(*) FROM cluster_resource_uses WHERE id = ?', confirmation_row_id)).to eq(0)
    expect(sql_value('SELECT done FROM transaction_confirmations WHERE transaction_id = ?', tx1)).to eq(1)
    expect(
      sql_value(
        'SELECT COUNT(*) FROM resource_locks WHERE locked_by_type = ? AND locked_by_id = ?',
        'TransactionChain',
        chain_id
      )
    ).to eq(0)
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

  it 'keeps going after exec failure when the transaction is keep-going' do
    chain_id = insert_chain(size: 2, progress: 0)
    tx1 = insert_transaction(
      transaction_chain_id: chain_id,
      handle: NodeCtldSpec::TestHandles::FAIL_EXEC,
      reversible: NodeCtldSpec::TxState::TX_KEEP_GOING
    )
    tx2 = insert_transaction(
      transaction_chain_id: chain_id,
      handle: NodeCtldSpec::TestHandles::OK,
      depends_on_id: tx1
    )

    execute_and_save(tx1)

    expect(sql_value('SELECT done FROM transactions WHERE id = ?', tx1)).to eq(1)
    expect(sql_value('SELECT status FROM transactions WHERE id = ?', tx1)).to eq(0)
    expect(transaction_output(tx1)).to include('error' => 'exec failed')
    expect(sql_value('SELECT state FROM transaction_chains WHERE id = ?', chain_id)).to eq(
      NodeCtldSpec::TxState::CHAIN_QUEUED
    )
    expect(sql_value('SELECT progress FROM transaction_chains WHERE id = ?', chain_id)).to eq(1)
    expect(sql_value('SELECT done FROM transactions WHERE id = ?', tx2)).to eq(0)
  end

  it 'keeps going after an intermediate failure and closes with the tail success' do
    chain_id = insert_chain(size: 3, progress: 0)
    failed_row_id = insert_cluster_resource_use(confirmed: 0)
    tail_row_id = insert_cluster_resource_use(confirmed: 1)
    tx1 = insert_transaction(
      transaction_chain_id: chain_id,
      handle: NodeCtldSpec::TestHandles::OK,
      reversible: NodeCtldSpec::TxState::TX_NOT_REVERSIBLE
    )
    tx2 = insert_transaction(
      transaction_chain_id: chain_id,
      handle: NodeCtldSpec::TestHandles::FAIL_EXEC,
      depends_on_id: tx1,
      reversible: NodeCtldSpec::TxState::TX_KEEP_GOING
    )
    tx3 = insert_transaction(
      transaction_chain_id: chain_id,
      handle: NodeCtldSpec::TestHandles::OK,
      depends_on_id: tx2,
      reversible: NodeCtldSpec::TxState::TX_NOT_REVERSIBLE
    )
    insert_confirmation(
      transaction_id: tx2,
      class_name: 'ClusterResourceUse',
      table_name: 'cluster_resource_uses',
      row_pks: { 'id' => failed_row_id },
      confirm_type: 0
    )
    insert_confirmation(
      transaction_id: tx3,
      class_name: 'ClusterResourceUse',
      table_name: 'cluster_resource_uses',
      row_pks: { 'id' => tail_row_id },
      attr_changes: { 'confirmed' => 2 },
      confirm_type: 3
    )

    execute_and_save(tx1)
    execute_and_save(tx2)

    expect(chain_state(chain_id)).to eq(
      'state' => NodeCtldSpec::TxState::CHAIN_QUEUED,
      'progress' => 2
    )
    expect(tx_state(tx2)).to eq(
      'done' => NodeCtldSpec::TxState::TX_DONE_DONE,
      'status' => NodeCtldSpec::TxState::TX_STATUS_FAILED
    )
    expect(transaction_output(tx2)).to include('error' => 'exec failed')
    expect(tx_state(tx3)).to include('done' => NodeCtldSpec::TxState::TX_DONE_WAITING)

    execute_and_save(tx3)

    expect(chain_state(chain_id)).to eq(
      'state' => NodeCtldSpec::TxState::CHAIN_DONE,
      'progress' => 3
    )
    expect(tx_state(tx3)).to eq(
      'done' => NodeCtldSpec::TxState::TX_DONE_DONE,
      'status' => NodeCtldSpec::TxState::TX_STATUS_OK
    )
    expect(tx_state(tx2)).to eq(
      'done' => NodeCtldSpec::TxState::TX_DONE_DONE,
      'status' => NodeCtldSpec::TxState::TX_STATUS_FAILED
    )
    expect(sql_value('SELECT COUNT(*) FROM cluster_resource_uses WHERE id = ?', failed_row_id)).to eq(0)
    expect(sql_value('SELECT confirmed FROM cluster_resource_uses WHERE id = ?', tail_row_id)).to eq(2)
  end

  it 'clears signatures and releases locks and ports on non-fatal close' do
    chain_id = insert_chain(size: 2, progress: 1)
    tx1 = insert_transaction(
      transaction_chain_id: chain_id,
      handle: NodeCtldSpec::TestHandles::OK,
      done: NodeCtldSpec::TxState::TX_DONE_DONE,
      status: NodeCtldSpec::TxState::TX_STATUS_OK,
      signature: 'sig-one'
    )
    payload, signature = NodeCtldSpec::SigningHelpers.signed_input(
      chain_id: chain_id,
      depends_on_id: tx1,
      handle: NodeCtldSpec::TestHandles::OK,
      node_id: NodeCtldSpec::BaselineSeed.ids.fetch(:node_id),
      reversible: NodeCtldSpec::TxState::TX_REVERSIBLE,
      input: {}
    )
    tx2 = insert_transaction(
      transaction_chain_id: chain_id,
      handle: NodeCtldSpec::TestHandles::OK,
      depends_on_id: tx1,
      input: payload,
      signature: signature
    )
    insert_resource_lock(chain_id: chain_id)
    port_id = insert_port_reservation(chain_id: chain_id)

    execute_and_save(tx2)

    expect(
      sql_value(
        'SELECT COUNT(*) FROM transactions WHERE transaction_chain_id = ? ' \
        'AND signature IS NOT NULL',
        chain_id
      )
    ).to eq(0)
    expect(
      sql_value(
        'SELECT COUNT(*) FROM resource_locks WHERE locked_by_type = ' \
        '\'TransactionChain\' AND locked_by_id = ?',
        chain_id
      )
    ).to eq(0)
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

  it 'closes the chain as fatal when rollback fails in rollback mode' do
    chain_id = insert_chain(
      state: NodeCtldSpec::TxState::CHAIN_ROLLBACKING,
      size: 1,
      progress: 0
    )
    tx_id = insert_transaction(
      transaction_chain_id: chain_id,
      handle: NodeCtldSpec::TestHandles::FAIL_ROLLBACK,
      reversible: NodeCtldSpec::TxState::TX_REVERSIBLE
    )
    insert_resource_lock(chain_id: chain_id)
    insert_port_reservation(chain_id: chain_id)

    execute_and_save(tx_id)

    expect(sql_value('SELECT done FROM transactions WHERE id = ?', tx_id)).to eq(2)
    expect(sql_value('SELECT state FROM transaction_chains WHERE id = ?', chain_id)).to eq(
      NodeCtldSpec::TxState::CHAIN_FATAL
    )
    expect(
      sql_value(
        'SELECT COUNT(*) FROM resource_locks WHERE locked_by_type = ' \
        '\'TransactionChain\' AND locked_by_id = ?',
        chain_id
      )
    ).to eq(1)
    expect(
      sql_value(
        'SELECT COUNT(*) FROM port_reservations WHERE transaction_chain_id = ?',
        chain_id
      )
    ).to eq(1)
  end
end
