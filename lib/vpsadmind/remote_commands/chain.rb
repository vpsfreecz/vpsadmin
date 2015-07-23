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
                      confirm_type, done, id
               FROM transaction_confirmations c
               INNER JOIN transactions t ON t.t_id = c.transaction_id
               WHERE t.transaction_chain_id = ?', @chain
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

            unless @transactions
              @transactions = []

              st = db.prepared_st(
                  'SELECT t_id FROM transactions
                   WHERE transaction_chain_id = ?
                   ORDER BY t_id',
                  @chain
              )

              st.each do |row|
                @transactions << row[0]
              end

              st.close
            end

            out = {
                :transactions => c.force_run(t, @transactions, @direction.to_sym, @success)
            }
          end
          
      end
      
      db.close
      
      ok.update({:output => out})
    end
  end
end
