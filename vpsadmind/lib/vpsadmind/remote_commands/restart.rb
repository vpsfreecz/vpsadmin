module VpsAdmind::RemoteCommands
  class Restart < Base
    handle :restart
    needs :worker, :subprocess

    def exec
      VpsAdmind::Daemon.safe_exit(VpsAdmind::EXIT_RESTART)

      if @force
        walk_workers { |w| :silent }
        drop_workers
        killall_subprocesses
      end

      ok
    end
  end
end
