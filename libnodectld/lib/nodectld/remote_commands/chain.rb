module NodeCtld::RemoteCommands
  class Chain < Base
    handle :chain

    def exec
      db = ::NodeCtld::Db.new
      out = {}

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
              row_pks: YAML.load(row['row_pks']),
              attr_changes: row['attr_changes'] ? YAML.load(row['attr_changes']) : nil,
              type: NodeCtld::Confirmations.translate_type(row['confirm_type']),
              done: row['done'] == 1 ? true : false
            }
          end

          out = {transactions: ret}

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
          db.prepared('UPDATE transaction_chains SET state = 6 WHERE id = ?', @chain)
      end

      db.close

      ok.update({output: out})
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
          created_at: lock['created_at'],
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
          port: lock['port'],
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
  end
end
