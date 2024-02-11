module NodeCtld::RemoteCommands
  class Queue < Base
    handle :queue

    def exec
      case @command
      when 'pause'
        @daemon.queues do |queues|
          q = queues[@queue.to_sym]
          return { ret: :error, output: 'queue not found' } if q.nil?

          q.pause(@duration)
        end

      when 'resume'
        @daemon.queues do |queues|
          if @queue == 'all'
            queues.each_value(&:resume)
          else
            q = queues[@queue.to_sym]
            return { ret: :error, output: 'queue not found' } if q.nil?

            q.resume
          end
        end

      when 'resize'
        @daemon.queues do |queues|
          q = queues[@queue.to_sym]
          return { ret: :error, output: 'queue not found' } if q.nil?
        end

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
