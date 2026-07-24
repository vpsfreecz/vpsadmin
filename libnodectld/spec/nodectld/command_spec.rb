# frozen_string_literal: true

require 'digest'
require 'spec_helper'
require 'stringio'
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

  def insert_event(routing_state: 1)
    sql_insert('events', {
      event_type: 'user.test_notification',
      category: 'user',
      severity: 0,
      subject: 'libnodectld transaction-gated notification',
      routing_state: routing_state,
      parameters: '{}',
      created_at: Time.now.utc,
      updated_at: Time.now.utc
    })
  end

  def insert_event_delivery(
    event_id:,
    transaction_id:,
    state:,
    attempt_count: 0,
    mail_log_id: nil,
    event_delivery_group_id: nil,
    released_at: nil
  )
    sql_insert('event_deliveries', {
      event_id: event_id,
      action: 'email',
      target_kind: 0,
      target_value: 'default',
      target_label: 'Default recipient',
      state: state,
      attempt_count: attempt_count,
      mail_log_id: mail_log_id,
      event_delivery_group_id: event_delivery_group_id,
      released_at: released_at,
      transaction_id: transaction_id,
      created_at: Time.now.utc,
      updated_at: Time.now.utc
    })
  end

  def insert_event_delivery_group(next_flush_at:)
    sql_insert('event_delivery_groups', {
      action: 'email',
      group_key: Digest::SHA256.hexdigest("libnodectld-group-#{next_flush_at.to_f}"),
      labels: '{}',
      group_wait_seconds: 30,
      group_interval_seconds: 300,
      next_flush_at: next_flush_at,
      created_at: Time.now.utc,
      updated_at: Time.now.utc
    })
  end

  def insert_mail_log
    sql_insert('mail_logs', {
      to: 'recipient@example.test',
      cc: '',
      bcc: '',
      from: 'noreply@example.test',
      subject: 'libnodectld transaction-gated notification',
      text_plain: 'libnodectld transaction-gated notification body',
      created_at: Time.now.utc,
      updated_at: Time.now.utc
    })
  end

  def insert_event_delivery_attempt(delivery_id)
    sql_insert('event_delivery_attempts', {
      event_delivery_id: delivery_id,
      action: 'email',
      state: 2,
      attempt_number: 1,
      error_summary: 'already attempted',
      started_at: Time.now.utc,
      finished_at: Time.now.utc,
      created_at: Time.now.utc,
      updated_at: Time.now.utc
    })
  end

  def direction_output(tx_id, direction)
    transaction_output(tx_id).fetch(direction.to_s)
  end

  def capture_logs
    log_io = StringIO.new
    OsCtl::Lib::Logger.setup(:io, io: log_io)
    yield
    log_io.string
  ensure
    OsCtl::Lib::Logger.setup(:none)
  end

  def expect_log_to_include(log, *parts)
    parts.each { |part| expect(log).to include(part) }
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
    expect(direction_output(tx_id, :execute)).to include(
      'status' => 'failed',
      'error' => 'Unsupported command'
    )
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
    expect(direction_output(tx_id, :execute)).to include(
      'status' => 'failed',
      'error' => 'Bad input syntax'
    )
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
    expect(direction_output(tx_id, :execute)).to include(
      'status' => 'failed',
      'cmd' => 'process handler return value',
      'exitstatus' => 1
    )
    expect(direction_output(tx_id, :execute).fetch('error')).to include(
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
    expect(direction_output(tx_id, :execute)).to include(
      'status' => 'failed',
      'error' => 'Invalid signature'
    )
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
    expect(direction_output(tx_id, :execute)).to include(
      'status' => 'failed',
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

  it 'publishes transaction chain state changes after saving the chain' do
    chain_id = insert_chain
    tx_id = insert_transaction(
      transaction_chain_id: chain_id,
      handle: NodeCtldSpec::TestHandles::OK
    )
    allow(NodeCtld::TransactionChainEvents).to receive(:publish)

    execute_and_save(tx_id)

    expect(NodeCtld::TransactionChainEvents).to have_received(:publish).with(
      chain_id:,
      previous_state: NodeCtldSpec::TxState::CHAIN_QUEUED,
      state: NodeCtldSpec::TxState::CHAIN_DONE
    )
  end

  it 'publishes chain state changes with subsecond event time' do
    stub_node_bunny
    now = Time.at(1_780_000_000, 123_456)
    payload = nil
    allow(Time).to receive(:now).and_return(now)
    allow(NodeCtld::NodeBunny).to receive(:publish_drop) do |_exchange, body, **opts|
      expect(opts).to include(
        routing_key: NodeCtld::TransactionChainEvents::ROUTING_KEY,
        persistent: true
      )
      payload = JSON.parse(body)
    end

    NodeCtld::TransactionChainEvents.publish(
      chain_id: 42,
      previous_state: NodeCtldSpec::TxState::CHAIN_QUEUED,
      state: NodeCtldSpec::TxState::CHAIN_DONE
    )

    events = payload.fetch('events')
    expect(events.size).to eq(1)
    expect(events.first).to include(
      'chain_id' => 42,
      'previous_state' => 'queued',
      'state' => 'done',
      'time' => now.to_i,
      'time_f' => now.to_f
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
    expect(direction_output(tx_id, :execute)).to include(
      'status' => 'ok',
      'handler' => 'ok'
    )
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

    expect(direction_output(tx_id, :execute)).to include(
      'status' => 'failed',
      'error' => 'Killed'
    )
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
    output = transaction_output(tx_id)
    expect(output).not_to have_key('error')
    expect(output.fetch('execute')).to include(
      'status' => 'failed',
      'cmd' => 'spec-fail-exec',
      'exitstatus' => 23,
      'error' => 'exec failed'
    )
    expect(output.fetch('rollback')).to include(
      'status' => 'ok',
      'rolled_back' => true
    )
  end

  it 'preserves exec and rollback failures from the same transaction' do
    chain_id = insert_chain
    tx_id = insert_transaction(
      transaction_chain_id: chain_id,
      handle: NodeCtldSpec::TestHandles::FAIL_EXEC_AND_ROLLBACK,
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

    output = transaction_output(tx_id)
    expect(output.fetch('execute')).to include(
      'status' => 'failed',
      'cmd' => 'spec-fail-exec',
      'exitstatus' => 23,
      'error' => 'exec failed'
    )
    expect(output.fetch('rollback')).to include(
      'status' => 'failed',
      'cmd' => 'spec-fail-rollback',
      'exitstatus' => 42,
      'error' => 'rollback failed'
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
    expect(direction_output(tx_id, :execute).fetch('error')).to include(
      'generic failure from spec handler'
    )
    expect(direction_output(tx_id, :rollback)).to include('status' => 'ok')
  end

  it 'aborts unsent transaction-gated event deliveries when a chain fails' do
    chain_id = insert_chain(size: 1, progress: 0)
    tx_id = insert_transaction(
      transaction_chain_id: chain_id,
      handle: NodeCtldSpec::TestHandles::FAIL_EXEC,
      reversible: NodeCtldSpec::TxState::TX_REVERSIBLE
    )
    unsent_event_id = insert_event
    unsent_delivery_id = insert_event_delivery(
      event_id: unsent_event_id,
      transaction_id: tx_id,
      state: described_class::EVENT_DELIVERY_STATE_PREPARED
    )
    unsent_mail_event_id = insert_event
    unsent_mail_delivery_id = insert_event_delivery(
      event_id: unsent_mail_event_id,
      transaction_id: tx_id,
      state: described_class::EVENT_DELIVERY_STATE_PREPARED,
      mail_log_id: insert_mail_log
    )
    first_member_at = Time.now.utc
    survivor_member_at = first_member_at + 120
    group_id = insert_event_delivery_group(next_flush_at: first_member_at + 30)
    grouping_event_id = insert_event
    grouping_delivery_id = insert_event_delivery(
      event_id: grouping_event_id,
      transaction_id: tx_id,
      state: described_class::EVENT_DELIVERY_STATE_GROUPING,
      event_delivery_group_id: group_id,
      released_at: first_member_at
    )
    survivor_event_id = insert_event
    survivor_delivery_id = insert_event_delivery(
      event_id: survivor_event_id,
      transaction_id: nil,
      state: described_class::EVENT_DELIVERY_STATE_GROUPING,
      event_delivery_group_id: group_id,
      released_at: survivor_member_at
    )
    attempted_event_id = insert_event
    attempted_delivery_id = insert_event_delivery(
      event_id: attempted_event_id,
      transaction_id: tx_id,
      state: described_class::EVENT_DELIVERY_STATE_RELEASED,
      attempt_count: 1
    )
    insert_event_delivery_attempt(attempted_delivery_id)

    execute_and_save(tx_id)

    expect(sql_value('SELECT state FROM event_deliveries WHERE id = ?', unsent_delivery_id)).to eq(
      described_class::EVENT_DELIVERY_STATE_ABORTED
    )
    expect(sql_value('SELECT routing_state FROM events WHERE id = ?', unsent_event_id)).to eq(
      described_class::EVENT_ROUTING_STATE_ABORTED
    )
    expect(sql_value('SELECT state FROM event_deliveries WHERE id = ?', unsent_mail_delivery_id)).to eq(
      described_class::EVENT_DELIVERY_STATE_ABORTED
    )
    expect(sql_value('SELECT mail_log_id FROM event_deliveries WHERE id = ?', unsent_mail_delivery_id)).not_to be_nil
    expect(sql_value('SELECT routing_state FROM events WHERE id = ?', unsent_mail_event_id)).to eq(
      described_class::EVENT_ROUTING_STATE_ABORTED
    )
    expect(sql_value('SELECT state FROM event_deliveries WHERE id = ?', grouping_delivery_id)).to eq(
      described_class::EVENT_DELIVERY_STATE_ABORTED
    )
    expect(sql_value('SELECT routing_state FROM events WHERE id = ?', grouping_event_id)).to eq(
      described_class::EVENT_ROUTING_STATE_ABORTED
    )
    expect(sql_value('SELECT state FROM event_deliveries WHERE id = ?', survivor_delivery_id)).to eq(
      described_class::EVENT_DELIVERY_STATE_GROUPING
    )
    expect(
      sql_value('SELECT next_flush_at FROM event_delivery_groups WHERE id = ?', group_id)
    ).to be_within(1.second).of(survivor_member_at + 30)
    expect(sql_value('SELECT error_summary FROM event_deliveries WHERE id = ?', unsent_delivery_id)).to include(
      "transaction chain ##{chain_id} failed"
    )
    expect(sql_value('SELECT state FROM event_deliveries WHERE id = ?', attempted_delivery_id)).to eq(
      described_class::EVENT_DELIVERY_STATE_RELEASED
    )
    expect(sql_value('SELECT routing_state FROM events WHERE id = ?', attempted_event_id)).to eq(1)
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
    expect(direction_output(tx_id, :execute)).to include(
      'status' => 'failed',
      'error' => 'Command not implemented'
    )
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
    expect(direction_output(tx2, :execute)).to include(
      'status' => 'failed',
      'error' => 'Unsupported command'
    )
    expect(transaction_output(tx3)).to eq(
      'execute' => {
        'status' => 'failed',
        'error' => 'Dependency failed'
      }
    )
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
    expect(transaction_output(tx2)).to eq(
      'execute' => {
        'status' => 'failed',
        'error' => 'Dependency failed'
      }
    )
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
    output = transaction_output(tx2)
    expect(output.fetch('execute')).to include(
      'status' => 'failed',
      'cmd' => 'spec-fail-exec',
      'exitstatus' => 23,
      'error' => 'exec failed'
    )
    expect(output.fetch('rollback')).to include(
      'status' => 'ok',
      'rolled_back' => true
    )
    expect(transaction_output(tx3)).to eq(
      'execute' => {
        'status' => 'failed',
        'error' => 'Dependency failed'
      }
    )

    execute_and_save(tx1)

    expect(chain_state(chain_id)).to eq(
      'state' => NodeCtldSpec::TxState::CHAIN_FAILED,
      'progress' => 0
    )
    expect(tx_state(tx1)).to eq(
      'done' => NodeCtldSpec::TxState::TX_DONE_ROLLED_BACK,
      'status' => NodeCtldSpec::TxState::TX_STATUS_OK
    )
    output = transaction_output(tx1)
    expect(output.fetch('execute')).to include(
      'status' => 'ok',
      'handler' => 'ok'
    )
    expect(output.fetch('rollback')).to include(
      'status' => 'ok',
      'handler' => 'ok-rollback'
    )
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
    expect(direction_output(tx1, :execute)).to include(
      'status' => 'failed',
      'error' => 'exec failed'
    )
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
    expect(direction_output(tx2, :execute)).to include(
      'status' => 'failed',
      'error' => 'exec failed'
    )
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

  it 'wraps legacy execute output before recording rollback output' do
    chain_id = insert_chain(
      state: NodeCtldSpec::TxState::CHAIN_ROLLBACKING,
      size: 1,
      progress: 0
    )
    tx_id = insert_transaction(
      transaction_chain_id: chain_id,
      handle: NodeCtldSpec::TestHandles::OK,
      done: NodeCtldSpec::TxState::TX_DONE_DONE,
      status: NodeCtldSpec::TxState::TX_STATUS_OK
    )
    sql_update(
      'transactions',
      { output: { handler: 'legacy-ok' }.to_json },
      'id = ?',
      tx_id
    )

    execute_and_save(tx_id)

    output = transaction_output(tx_id)
    expect(output.fetch('execute')).to include(
      'status' => 'ok',
      'handler' => 'legacy-ok'
    )
    expect(output.fetch('rollback')).to include(
      'status' => 'ok',
      'handler' => 'ok-rollback'
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
    expect(direction_output(tx_id, :rollback)).to include(
      'status' => 'failed',
      'cmd' => 'spec-fail-rollback',
      'exitstatus' => 42,
      'error' => 'rollback failed'
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

  describe 'failure logging' do
    it 'logs direct command failures with transaction context' do
      chain_id = insert_chain
      tx_id = insert_transaction(
        transaction_chain_id: chain_id,
        handle: NodeCtldSpec::TestHandles::FAIL_EXEC,
        reversible: NodeCtldSpec::TxState::TX_NOT_REVERSIBLE
      )

      log = capture_logs { execute_and_save(tx_id) }

      expect_log_to_include(
        log,
        "chain=#{chain_id}",
        "trans=#{tx_id}",
        'direction=execute',
        "handle=#{NodeCtldSpec::TestHandles::FAIL_EXEC}",
        'handler=NodeCtldSpec::TestHandlers::FailExec',
        'Transaction failed',
        'cmd=spec-fail-exec',
        'exitstatus=23',
        'error=exec failed'
      )
    end

    it 'logs rollback failures with rollback direction' do
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

      log = capture_logs { execute_and_save(tx_id) }

      expect_log_to_include(
        log,
        "chain=#{chain_id}",
        "trans=#{tx_id}",
        'direction=rollback',
        'handler=NodeCtldSpec::TestHandlers::FailRollback',
        'cmd=spec-fail-rollback',
        'exitstatus=42',
        'error=rollback failed'
      )
    end

    it 'logs validation failures without an exception object' do
      chain_id = insert_chain
      tx_id = insert_transaction(transaction_chain_id: chain_id, handle: 123_456)

      log = capture_logs { execute_and_save(tx_id) }

      expect_log_to_include(
        log,
        "chain=#{chain_id}",
        "trans=#{tx_id}",
        'direction=execute',
        'handle=123456',
        'Transaction failed',
        'error=Unsupported command'
      )
    end

    it 'logs hard kills' do
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
      cmd.instance_variable_set(
        :@current_klass,
        NodeCtldSpec::TestHandlers::Ok.name
      )

      log = capture_logs do
        cmd.killed(true)
        cmd.save(shared_db)
      end

      expect_log_to_include(
        log,
        "chain=#{chain_id}",
        "trans=#{tx_id}",
        'direction=execute',
        'handler=NodeCtldSpec::TestHandlers::Ok',
        'error=Killed'
      )
    end

    it 'does not log follower dependency failures' do
      chain_id = insert_chain(size: 2, progress: 0)
      tx1 = insert_transaction(
        transaction_chain_id: chain_id,
        handle: NodeCtldSpec::TestHandles::FAIL_EXEC,
        reversible: NodeCtldSpec::TxState::TX_NOT_REVERSIBLE
      )
      insert_transaction(
        transaction_chain_id: chain_id,
        handle: NodeCtldSpec::TestHandles::OK,
        depends_on_id: tx1
      )

      log = capture_logs { execute_and_save(tx1) }

      expect(log).to include('error=exec failed')
      expect(log).not_to include('Dependency failed')
    end

    it 'does not log successful or warning transactions as failures' do
      chain_id = insert_chain(size: 2, progress: 0)
      tx1 = insert_transaction(
        transaction_chain_id: chain_id,
        handle: NodeCtldSpec::TestHandles::OK
      )
      tx2 = insert_transaction(
        transaction_chain_id: chain_id,
        handle: NodeCtldSpec::TestHandles::WARNING,
        depends_on_id: tx1
      )

      log = capture_logs do
        execute_and_save(tx1)
        execute_and_save(tx2)
      end

      expect(log).not_to include('Transaction failed')
    end
  end
end
