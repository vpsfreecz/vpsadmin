module VpsAdmind::RemoteCommands
  class Update < Base
    handle :update
    needs :worker, :subprocess

    def exec
      VpsAdmind::Daemon.safe_exit(VpsAdmind::EXIT_UPDATE)

      if @force
        walk_workers { |w| :silent }
        drop_workers
        killall_subprocesses
      end

      ok
    end
  end
end
