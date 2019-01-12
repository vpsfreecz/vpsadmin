module VpsAdmind::RemoteCommands
  class Stop < Base
    handle :stop
    needs :subprocess

    def exec
      VpsAdmind::Daemon.safe_exit(VpsAdmind::EXIT_STOP)

      if @force
        VpsAdmind::Worker.kill_all
        killall_subprocesses
      end

      ok
    end
  end
end
