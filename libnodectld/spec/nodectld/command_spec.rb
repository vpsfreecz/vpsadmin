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

  it 'persists an unsupported handle error' do
    chain_id = insert_chain
    tx_id = insert_transaction(transaction_chain_id: chain_id, handle: 123_456)

    cmd = build_command(tx_id)
    expect(cmd.execute).to be(false)
    cmd.save(shared_db)

    expect(transaction_output(tx_id)).to include('error' => 'Unsupported command')
    expect(sql_value('SELECT status FROM transactions WHERE id = ?', tx_id)).to eq(0)
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

    expect(transaction_output(tx_id)).to include('error' => 'Bad input syntax')
    expect(sql_value('SELECT status FROM transactions WHERE id = ?', tx_id)).to eq(0)
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

    expect(transaction_output(tx_id)).to include('error' => 'Invalid signature')
    expect(sql_value('SELECT status FROM transactions WHERE id = ?', tx_id)).to eq(0)
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

    expect(transaction_output(tx_id)).to include(
      'error' => 'Signed options do not match relational options'
    )
    expect(sql_value('SELECT status FROM transactions WHERE id = ?', tx_id)).to eq(0)
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

    expect(sql_value('SELECT done FROM transactions WHERE id = ?', tx_id)).to eq(1)
    expect(sql_value('SELECT status FROM transactions WHERE id = ?', tx_id)).to eq(0)
    expect(sql_value('SELECT state FROM transaction_chains WHERE id = ?', chain_id)).to eq(
      NodeCtldSpec::TxState::CHAIN_FAILED
    )
    expect(transaction_output(tx_id)).to include('error' => 'Command not implemented')
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

  it 'clears signatures and releases locks and ports on non-fatal close' do
    chain_id = insert_chain(size: 2, progress: 1)
    tx1 = insert_transaction(
      transaction_chain_id: chain_id,
      handle: NodeCtldSpec::TestHandles::OK,
      done: NodeCtldSpec::TxState::TX_DONE_DONE,
      status: NodeCtldSpec::TxState::TX_STATUS_OK,
      signature: 'sig-one'
    )
    tx2 = insert_transaction(
      transaction_chain_id: chain_id,
      handle: NodeCtldSpec::TestHandles::OK,
      depends_on_id: tx1,
      signature: 'sig-two'
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
