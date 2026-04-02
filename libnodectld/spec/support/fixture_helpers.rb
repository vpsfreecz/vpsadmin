# frozen_string_literal: true

module NodeCtldSpec
  module TxState
    CHAIN_STAGED = 0
    CHAIN_QUEUED = 1
    CHAIN_DONE = 2
    CHAIN_ROLLBACKING = 3
    CHAIN_FAILED = 4
    CHAIN_FATAL = 5
    CHAIN_RESOLVED = 6

    TX_STATUS_FAILED = 0
    TX_STATUS_OK = 1
    TX_STATUS_WARNING = 2

    TX_DONE_WAITING = 0
    TX_DONE_DONE = 1
    TX_DONE_ROLLED_BACK = 2

    TX_NOT_REVERSIBLE = 0
    TX_REVERSIBLE = 1
    TX_KEEP_GOING = 2
  end

  module FixtureHelpers
    def insert_chain(state: TxState::CHAIN_QUEUED, size: 1, progress: 0, urgent_rollback: 0,
                     name: 'spec', type: 'Spec::Chain', user_id: nil)
      now = Time.now.utc

      sql_insert('transaction_chains', {
        name: name,
        type: type,
        state: state,
        size: size,
        progress: progress,
        user_id: user_id,
        created_at: now,
        updated_at: now,
        urgent_rollback: urgent_rollback,
        concern_type: 0,
        user_session_id: nil
      })
    end

    def insert_transaction(transaction_chain_id:, handle:,
                           node_id: NodeCtldSpec::BaselineSeed.ids.fetch(:node_id),
                           depends_on_id: nil,
                           user_id: nil,
                           reversible: TxState::TX_REVERSIBLE,
                           status: TxState::TX_STATUS_FAILED,
                           done: TxState::TX_DONE_WAITING,
                           input: nil,
                           signature: nil,
                           queue: 'general',
                           priority: 0,
                           urgent: 0,
                           vps_id: nil)
      input =
        if input.nil?
          {
            transaction_chain: transaction_chain_id,
            depends_on: depends_on_id,
            handle: handle,
            node: node_id,
            reversible: reversible,
            input: {}
          }.to_json
        elsif input.is_a?(String)
          input
        else
          input.to_json
        end

      sql_insert('transactions', {
        user_id: user_id,
        node_id: node_id,
        vps_id: vps_id,
        handle: handle,
        depends_on_id: depends_on_id,
        urgent: urgent,
        priority: priority,
        status: status,
        done: done,
        input: input,
        output: nil,
        transaction_chain_id: transaction_chain_id,
        reversible: reversible,
        created_at: Time.now.utc,
        started_at: nil,
        finished_at: nil,
        queue: queue,
        signature: signature
      })
    end

    def insert_confirmation(transaction_id:, class_name:, table_name:, row_pks:,
                            confirm_type:, attr_changes: nil, done: 0)
      sql_insert('transaction_confirmations', {
        transaction_id: transaction_id,
        class_name: class_name,
        table_name: table_name,
        row_pks: YAML.dump(row_pks),
        attr_changes: attr_changes.nil? ? nil : YAML.dump(attr_changes),
        confirm_type: confirm_type,
        done: done,
        created_at: Time.now.utc,
        updated_at: Time.now.utc
      })
    end

    def insert_resource_lock(chain_id:, resource: 'SpecLock', row_id: nil, created_at: Time.now.utc,
                             updated_at: Time.now.utc)
      row_id ||= next_row_id('resource_locks', 'row_id')

      sql_insert('resource_locks', {
        resource: resource,
        row_id: row_id,
        created_at: created_at,
        updated_at: updated_at,
        locked_by_id: chain_id,
        locked_by_type: 'TransactionChain'
      })
    end

    def insert_port_reservation(chain_id:, node_id: NodeCtldSpec::BaselineSeed.ids.fetch(:node_id),
                                addr: '192.0.2.250', port: nil)
      port ||= next_port

      sql_insert('port_reservations', {
        node_id: node_id,
        addr: addr,
        port: port,
        transaction_chain_id: chain_id
      })
    end

    def insert_cluster_resource_use(user_cluster_resource_id: NodeCtldSpec::BaselineSeed.ids.fetch(:user_cluster_resource_id),
                                    class_name: 'SpecRecord',
                                    table_name: 'spec_records',
                                    row_id: nil,
                                    value: 10,
                                    confirmed: 0,
                                    admin_lock_type: 0,
                                    admin_limit: nil,
                                    enabled: 1)
      row_id ||= next_row_id('cluster_resource_uses', 'row_id')

      sql_insert('cluster_resource_uses', {
        user_cluster_resource_id: user_cluster_resource_id,
        class_name: class_name,
        table_name: table_name,
        row_id: row_id,
        value: value,
        confirmed: confirmed,
        admin_lock_type: admin_lock_type,
        admin_limit: admin_limit,
        enabled: enabled
      })
    end

    def joined_transaction_row(tx_id)
      sql_row(
        'SELECT t.*,
                ch.state AS chain_state,
                ch.progress AS chain_progress,
                ch.size AS chain_size,
                ch.urgent_rollback AS chain_urgent_rollback
           FROM transactions t
           INNER JOIN transaction_chains ch ON ch.id = t.transaction_chain_id
          WHERE t.id = ?',
        tx_id
      )
    end

    private

    def next_row_id(table, column)
      sql_value("SELECT COALESCE(MAX(`#{column}`), 0) + 1 FROM #{table}").to_i
    end

    def next_port
      sql_value('SELECT COALESCE(MAX(port), 39000) + 1 FROM port_reservations').to_i
    end
  end
end
