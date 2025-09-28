module NodeCtld::Utils
  module Worker
    def walk_workers
      killed = 0

      @daemon.queues.each_value do |queue|
        queue.each_value do |w|
          ret = yield(w)

          next unless ret

          log "Killing transaction #{w.cmd.id}"
          w.kill(ret != :silent)
          killed += 1
        end
      end

      killed
    end

    def drop_workers
      @daemon.queues do |queues|
        queues.each_value(&:clear!)
      end
    end
  end
end
