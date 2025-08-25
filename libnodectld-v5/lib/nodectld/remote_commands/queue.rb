module NodeCtld::RemoteCommands
  class Queue < Base
    handle :queue

    def exec
      case @command
      when 'pause'
        q = @daemon.queues[@queue.to_sym]
        return { ret: :error, output: 'queue not found' } if q.nil?

        q.pause(@duration)

      when 'resume'
        if @queue == 'all'
          @daemon.queues.each_value(&:resume)
        else
          q = @daemon.queues[@queue.to_sym]
          return { ret: :error, output: 'queue not found' } if q.nil?

          q.resume
        end

      when 'resize'
        q = @daemon.queues[@queue.to_sym]
        return { ret: :error, output: 'queue not found' } if q.nil?

        $CFG.patch({
                     vpsadmin: {
                       queues: {
                         @queue.to_sym => {
                           threads: @size
                         }
                       }
                     }
                   })

      else
        return { ret: :error, output: 'unknown command' }
      end

      ok
    end
  end
end
