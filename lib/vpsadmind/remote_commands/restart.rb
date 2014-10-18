module VpsAdmind::RemoteCommands
  class Restart < Base
    handle :restart

    def exec
      VpsAdmind::Daemon.safe_exit(VpsAdmind::EXIT_RESTART)

      if @force
        walk_workers { |w| :silent }
        drop_workers
      end

      ok
    end
  end
end
