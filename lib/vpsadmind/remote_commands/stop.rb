module VpsAdmind::RemoteCommands
  class Stop < Base
    handle :stop
    needs :worker, :subprocess

    def exec
      VpsAdmind::Daemon.safe_exit(VpsAdmind::EXIT_STOP)

      if @force
        walk_workers { |w| :silent }
        drop_workers
        killall_subprocesses
      end

      ok
    end
  end
end
