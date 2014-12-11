module VpsAdmind
  class CommandFailed < StandardError
    attr_reader :cmd, :rc, :output

    def initialize(cmd, rc, out)
      @cmd = cmd
      @rc = rc
      @output = out
    end

    def message
      "command '#{@cmd}' exited with code '#{@rc}', output: '#{@output}'"
    end
  end

  class CommandNotImplemented < StandardError

  end

  class Command
    include Utils::Compat
    include Utils::Log
    extend Utils::Log

    attr_reader :trans

    @@handlers = {}

    def initialize(trans)
      @trans = trans
      @output = {}
      @status = :failed
      @m_attr = Mutex.new
    end

    def execute
      klass = handler

      unless klass
        @output[:error] = "Unsupported command"
        return false
      end

      begin
        param = JSON.parse(@trans["t_param"])
      rescue
        @output[:error] = "Bad param syntax"
        return false
      end

      param[:vps_id] = @trans['t_vps'].to_i

      @cmd = class_from_name(klass).new(self, param)

      @m_attr.synchronize { @time_start = Time.new.to_i }

      begin
        ret = @cmd.exec

        begin
          @status = ret[:ret]

          if @status == nil
            bad_value(klass)
          end
        rescue
          bad_value(klass)
        end
      rescue CommandFailed => err
        @status = :failed
        @output[:cmd] = err.cmd
        @output[:exitstatus] = err.rc
        @output[:error] = err.output
      rescue CommandNotImplemented
        @status = :failed
        @output[:error] = "Command not implemented"
      rescue => err
        @status = :failed
        @output[:error] = err.inspect
        @output[:backtrace] = err.backtrace
        p @output
      end

      fallback if @status == :failed

      @time_end = Time.new.to_i
    end

    def bad_value(klass)
      raise CommandFailed.new("process handler return value", 1, "#{klass} did not return expected value")
    end

    def save(db)
      success = @status != :failed

      db.transaction do |t|
        st = t.prepared_st('SELECT table_name, row_pks, attr_changes, confirm_type FROM transaction_confirmations WHERE transaction_id = ? AND done = 0', @trans['t_id'])

        st.each do |row|
          pk = pk_cond(YAML.load(row[1]))

          case row[3].to_i
            when 0 # create
              if success
                t.query("UPDATE #{row[0]} SET confirmed = 1 WHERE #{pk}")
              else
                t.query("DELETE FROM #{row[0]} WHERE #{pk}")
              end

            when 1 # edit before
              unless success
                attrs = YAML.load(row[2])
                update = attrs.collect { |k, v| "`#{k}` = #{sql_val(v)}" }.join(',')

                t.query("UPDATE #{row[0]} SET #{update} WHERE #{pk}")
              end

            when 2 # edit after
              if success
                attrs = YAML.load(row[2])
                update = attrs.collect { |k, v| "`#{k}` = #{sql_val(v)}" }.join(',')

                t.query("UPDATE #{row[0]} SET #{update} WHERE #{pk}")
              end

            when 3 # destroy
              if success
                t.query("DELETE FROM #{row[0]} WHERE #{pk}")
              else
                t.query("UPDATE #{row[0]} SET confirmed = 1 WHERE #{pk}")
              end

            when 4 # just destroy
              if success
                t.query("DELETE FROM #{row[0]} WHERE #{pk}")
              end

            when 5 # decrement
              if success
                attr = YAML.load(row[2])

                t.query("UPDATE #{row[0]} SET #{attr} = #{attr} - 1 WHERE #{pk}")
              end

            when 6 # increment
              if success
                attr = YAML.load(row[2])

                t.query("UPDATE #{row[0]} SET #{attr} = #{attr} + 1 WHERE #{pk}")
              end
          end
        end

        st.close

        t.prepared('UPDATE transaction_confirmations SET done = 1 WHERE transaction_id = ? AND done = 0', @trans['t_id'])

        db.prepared(
            'UPDATE transactions SET t_done=1, t_success=?, t_output=?, t_real_start=?, t_end=? WHERE t_id=?',
            {:failed => 0, :ok => 1, :warning => 2}[@status], (@cmd ? @output.merge(@cmd.output) : @output).to_json, @time_start, @time_end, @trans['t_id']
        )

        st = t.prepared_st('SELECT COUNT(*)
                      FROM transaction_chains c
                      INNER JOIN transactions t ON c.id = t.transaction_chain_id
                      WHERE id = ? AND t_done = 0', @trans['transaction_chain_id'])

        cnt = st.fetch[0].to_i
        st.close

        if cnt == 0
          # mark chain as finished
          t.prepared('UPDATE transaction_chains SET `state` = 2, `progress` = `progress` + 1 WHERE id = ?', @trans['transaction_chain_id'])

          # release all locks
          t.prepared('DELETE FROM resource_locks WHERE transaction_chain_id = ?', @trans['transaction_chain_id'])
        else
          t.prepared('UPDATE transaction_chains SET `progress` = `progress` + 1 WHERE id = ?', @trans['transaction_chain_id'])
        end

        @cmd.post_save(db) if @cmd
      end
    end

    def dependency_failed(db)
      @output[:error] = 'Dependency failed'
      @status = :failed
      save(db)
    end

    def killed(hard)
      @cmd.killed

      if hard
        @output[:error] = 'Killed'
        @status = :failed

        fallback
      end
    end

    def fallback
      @output[:fallback] = {}

      begin
        fallback = JSON.parse(@trans['t_fallback'])

        unless fallback.empty?
          log "Transaction #{@trans['t_id']} failed, falling back"

          transaction = Transaction.new
          @output[:fallback][:transactions] = []

          fallback['transactions'].each do |t|
            @output[:fallback][:transactions] << transaction.queue({
                 :m_id => t['t_m_id'],
                 :node => t['t_server'],
                 :vps => t['t_vps'],
                 :type => t['t_type'],
                 :depends => t['t_depends_on'],
                 :urgent => t['t_urgent'],
                 :priority => t['t_priority'],
                 :param => t['t_params'],
             })
          end
        end
      rescue => err
        @output[:fallback][:msg] = 'Fallback failed'
        @output[:fallback][:error] = err.inspect
        @output[:fallback][:backtrace] = err.backtrace
      end
    end

    def id
      @trans["t_id"]
    end

    def worker_id
      if @trans.has_key?("t_vps")
        @trans["t_vps"].to_i
      else
        0
      end
    end

    def type
      @trans["t_type"]
    end

    def urgent?
      @trans['t_urgent'].to_i == 1
    end

    def handler
      @@handlers[@trans["t_type"].to_i]
    end

    def step
      @cmd.step
    end

    def subtask
      @cmd.subtask
    end

    def time_start
      @m_attr.synchronize { @time_start }
    end

    def Command.register(klass, type)
      @@handlers[type] = klass
      log "Cmd ##{type} => #{klass}"
    end

    private
    def pk_cond(pks)
      pks.map { |k, v| "`#{k}` = #{sql_val(v)}" }.join(' AND ')
    end

    def sql_val(v)
      if v.is_a?(Integer)
        v
      elsif v.nil?
        'NULL'
      else
        "'#{v}'"
      end
    end
  end
end
