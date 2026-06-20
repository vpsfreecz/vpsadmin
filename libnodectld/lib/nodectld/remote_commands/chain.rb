require 'nodectld/transaction_chain_events'

module NodeCtld::RemoteCommands
  class Chain < Base
    handle :chain

    def exec
      db = ::NodeCtld::Db.new
      out = {}
      state_change = nil

      case @command
      when 'confirmations'
        ret = {}
        rs = db.prepared(
          'SELECT transaction_id, class_name, row_pks, attr_changes,
                    confirm_type, c.done, c.id
              FROM transaction_confirmations c
              INNER JOIN transactions t ON t.id = c.transaction_id
              WHERE t.transaction_chain_id = ?
              ORDER BY t.id', @chain
        )

        rs.each do |row|
          ret[row['transaction_id']] ||= []
          ret[row['transaction_id']] << {
            id: row['id'],
            class_name: row['class_name'],
            row_pks: load_yaml(row['row_pks']),
            attr_changes: row['attr_changes'] ? load_yaml(row['attr_changes']) : nil,
            type: NodeCtld::Confirmations.translate_type(row['confirm_type']),
            done: row['done'] == 1
          }
        end

        out = { transactions: ret }

      when 'confirm'
        db.transaction do |t|
          c = NodeCtld::Confirmations.new(@chain)
          transactions = @transactions

          unless transactions
            transactions = []

            rs = db.prepared(
              'SELECT id FROM transactions
                  WHERE transaction_chain_id = ?
                  ORDER BY id',
              @chain
            )

            rs.each do |row|
              transactions << row['id']
            end
          end

          out = {
            transactions: c.force_run(t, transactions, @direction.to_sym, @success)
          }
        end

      when 'release'
        db.transaction do |t|
          @release.each do |r|
            case r
            when 'locks'
              out[:locks] = release_locks(t)

            when 'ports'
              out[:ports] = release_ports(t)
            end
          end
        end

      when 'resolve'
        previous_state = chain_state(db, @chain)
        db.prepared('UPDATE transaction_chains SET state = 6 WHERE id = ?', @chain)
        state_change = [previous_state, 6]

      when 'retry'
        db.transaction do |t|
          state_change = retry_chain(t, @chain, @transactions && @transactions.first)
        end
      end

      db.close
      publish_state_change(state_change)

      ok.update({ output: out })
    end

    def release_locks(t)
      ret = []

      rs = t.prepared(
        "SELECT resource, row_id, created_at
        FROM resource_locks
        WHERE locked_by_type = 'TransactionChain' AND locked_by_id = ?",
        @chain
      )

      rs.each do |lock|
        ret << {
          resource: lock['resource'],
          row_id: lock['row_id'],
          created_at: lock['created_at']
        }
      end

      t.prepared(
        "DELETE FROM resource_locks
        WHERE locked_by_type = 'TransactionChain' AND locked_by_id = ?",
        @chain
      )

      ret
    end

    def release_ports(t)
      ret = []

      rs = t.prepared(
        'SELECT n.name, l.domain, r.node_id, r.addr, r.port
        FROM port_reservations r
        INNER JOIN nodes n ON n.id = r.node_id
        INNER JOIN locations l ON l.id = n.location_id
        WHERE transaction_chain_id = ?',
        @chain
      )

      rs.each do |lock|
        ret << {
          node_name: lock['name'],
          node_id: lock['node_id'],
          location_domain: lock['domain'],
          addr: lock['addr'],
          port: lock['port']
        }
      end

      t.prepared(
        'UPDATE port_reservations
        SET transaction_chain_id = NULL, addr = NULL
        WHERE transaction_chain_id = ?',
        @chain
      )

      ret
    end

    def retry_chain(t, chain_id, from_transaction_id)
      previous_state = chain_state(t, chain_id)

      if from_transaction_id
        # Check we have a valid transaction from the given chain
        rs = t.prepared(
          'SELECT id FROM transactions WHERE transaction_chain_id = ? AND id = ?',
          chain_id,
          from_transaction_id
        )

        if rs.count <= 0
          raise NodeCtld::RemoteCommandError,
                "Transaction #{from_transaction_id} not found in chain #{chain_id}"
        end

        # Mark transactions as queued
        t.prepared(
          'UPDATE transactions
          SET `done` = 0, `status` = 0
          WHERE transaction_chain_id = ? AND id >= ?',
          chain_id,
          from_transaction_id
        )
      else
        # Mark transactions as queued
        t.prepared(
          'UPDATE transactions
          SET `done` = 0, `status` = 0
          WHERE transaction_chain_id = ?',
          chain_id
        )
      end

      # Find new chain progress value
      progress = t.prepared(
        'SELECT COUNT(*) AS cnt
        FROM transactions
        WHERE transaction_chain_id = ? AND `done` = 1',
        chain_id
      ).get!['cnt']

      # Reopen chain
      t.prepared(
        'UPDATE transaction_chains SET state = 1, progress = ? WHERE id = ?',
        progress,
        chain_id
      )

      [previous_state, 1]
    end

    protected

    def chain_state(db, chain_id)
      db.prepared('SELECT state FROM transaction_chains WHERE id = ?', chain_id).get!['state'].to_i
    end

    def publish_state_change(change)
      return unless change

      previous_state, state = change
      return if previous_state.to_i == state.to_i

      NodeCtld::TransactionChainEvents.publish(
        chain_id: @chain,
        previous_state:,
        state:
      )
    rescue StandardError => e
      log(:warn, "unable to publish transaction chain event: #{e.class}: #{e.message}")
    end

    def load_yaml(v)
      YAML.safe_load(v, permitted_classes: [Symbol, Time])
    end
  end
end
