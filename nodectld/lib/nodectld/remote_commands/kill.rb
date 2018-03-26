module NodeCtld::RemoteCommands
  class Kill < Base
    handle :kill
    needs :worker

    def exec
      cnt = 0
      msgs = {}

      if @transactions == 'all'
        cnt = walk_workers { |w| true }

      elsif @types
        @types.each do |t|
          killed = walk_workers { |w| w.cmd.type == t }

          if killed == 0
            msgs[t] = 'No transaction with this type'
          end

          cnt += killed
        end

      else
        @transactions.each do |t|
          killed = walk_workers { |w| w.cmd.id == t }

          if killed == 0
            msgs[t] = 'No such transaction'
          end

          cnt += killed
        end
      end

      {ret: :ok, output: {killed: cnt, msgs: msgs}}
    end
  end
end
