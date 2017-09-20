module VpsAdmind::Utils
  module Worker
    def walk_workers
      killed = 0

      @daemon.queues do |queues|
        queues.each_value do |queue|
          queue.each do |wid, w|
            ret = yield(w)

            if ret
              log "Killing transaction #{w.cmd.id}"
              w.kill(ret != :silent)
              killed += 1
            end
          end
        end
      end

      killed
    end

    def drop_workers
      @daemon.queues do |queues|
        queues.each_value do |queue|
          queue.clear!
        end
      end
    end
  end
end
