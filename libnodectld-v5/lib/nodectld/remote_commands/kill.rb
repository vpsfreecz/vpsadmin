module NodeCtld::RemoteCommands
  class Kill < Base
    handle :kill
    needs :worker

    def exec
      cnt = 0
      msgs = {}

      if @transactions == 'all'
        cnt = walk_workers { |_w| true }

      elsif @types
        @types.each do |t|
          killed = walk_workers { |w| w.cmd.type == t }

          msgs[t] = 'No transaction with this type' if killed == 0

          cnt += killed
        end

      else
        @transactions.each do |t|
          killed = walk_workers { |w| w.cmd.id == t }

          msgs[t] = 'No such transaction' if killed == 0

          cnt += killed
        end
      end

      { ret: :ok, output: { killed: cnt, msgs: } }
    end
  end
end
