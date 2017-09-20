module VpsAdmind::RemoteCommands
  class Chain < Base
    handle :chain

    def exec
      db = ::VpsAdmind::Db.new
      out = {}
      
      case @command
        when 'confirmations'
          ret = {}
          st = db.prepared_st(
              'SELECT transaction_id, class_name, row_pks, attr_changes,
                      confirm_type, c.done, c.id
               FROM transaction_confirmations c
               INNER JOIN transactions t ON t.id = c.transaction_id
               WHERE t.transaction_chain_id = ?
               ORDER BY t.id', @chain
          )

          st.each do |row|
            ret[row[0]] ||= []
            ret[row[0]] << {
                :id => row[6],
                :class_name => row[1],
                :row_pks => YAML.load(row[2]),
                :attr_changes => row[3] ? YAML.load(row[3]) : nil,
                :type => VpsAdmind::Confirmations.translate_type(row[4]),
                :done => row[5] == 1 ? true : false
            }
          end

          st.close

          out = {:transactions => ret}

        when 'confirm'
          db.transaction do |t|
            c = VpsAdmind::Confirmations.new(@chain)
            transactions = @transactions

            unless transactions
              transactions = []

              st = db.prepared_st(
                  'SELECT id FROM transactions
                   WHERE transaction_chain_id = ?
                   ORDER BY id',
                  @chain
              )

              st.each do |row|
                transactions << row[0]
              end

              st.close
            end

            out = {
                :transactions => c.force_run(t, transactions, @direction.to_sym, @success)
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
          
      end
      
      db.close
      
      ok.update({:output => out})
    end

    def release_locks(t)
      ret = []

      st = t.prepared_st(
          "SELECT resource, row_id, created_at
          FROM resource_locks
          WHERE locked_by_type = 'TransactionChain' AND locked_by_id = ?",
          @chain
      )

      st.each do |lock|
        ret << {
            :resource => lock[0],
            :row_id => lock[1],
            :created_at => lock[2]
        }
      end

      st.close

      t.prepared("DELETE FROM resource_locks WHERE locked_by_type = 'TransactionChain' AND locked_by_id = ?", @chain)

      ret
    end

    def release_ports(t)
      ret = []

      st = t.prepared_st(
          'SELECT n.name, l.domain, r.node_id, r.addr, r.port
          FROM port_reservations r
          INNER JOIN nodes n ON n.id = r.node_id
          INNER JOIN locations l ON l.id = n.location_id
          WHERE transaction_chain_id = ?',
          @chain
      )

      st.each do |lock|
        ret << {
            :node_name => lock[0],
            :node_id => lock[2],
            :location_domain => lock[1],
            :addr => lock[3],
            :port => lock[4]
        }
      end

      st.close

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
