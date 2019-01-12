module VpsAdmind::RemoteCommands
  class Restart < Base
    handle :restart
    needs :subprocess

    def exec
      VpsAdmind::Daemon.safe_exit(VpsAdmind::EXIT_RESTART)

      if @force
        VpsAdmind::Worker.kill_all
        killall_subprocesses
      end

      ok
    end
  end
end
