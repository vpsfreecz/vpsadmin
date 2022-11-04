module NodeCtld::RemoteCommands
  class Queue < Base
    handle :queue

    def exec
      case @command
      when 'pause'
        @daemon.queues do |queues|
          q = queues[@queue.to_sym]
          return {ret: :error, output: 'queue not found'} if q.nil?

          q.pause(@duration)
        end

      when 'resume'
        @daemon.queues do |queues|
          q = queues[@queue.to_sym]
          return {ret: :error, output: 'queue not found'} if q.nil?

          q.resume
        end

      else
        return {ret: :error, output: 'unknown command'}
      end

      ok
    end
  end
end
