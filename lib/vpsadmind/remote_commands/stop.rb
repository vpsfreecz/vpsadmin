module VpsAdmind::RemoteCommands
  class Stop < Base
    handle :stop

    def exec
      VpsAdmind::Daemon.safe_exit(VpsAdmind::EXIT_STOP)

      if @force
        walk_workers { |w| :silent }
        drop_workers
      end

      ok
    end
  end
end
