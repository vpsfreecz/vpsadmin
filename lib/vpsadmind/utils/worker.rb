module VpsAdmind::Utils
  module Worker
    def walk_workers
      killed = 0

      @daemon.workers do |workers|
        workers.each do |wid, w|
          ret = yield(w)

          if ret
            log "Killing transaction #{w.cmd.id}"
            w.kill(ret != :silent)
            killed += 1
          end
        end
      end

      killed
    end

    def drop_workers
      @daemon.workers { |w| w.clear }
    end
  end
end
