module VpsAdmind::RemoteCommands
  class Update < Base
    handle :update
    needs :subprocess

    def exec
      VpsAdmind::Daemon.safe_exit(VpsAdmind::EXIT_UPDATE)

      if @force
        VpsAdmind::Worker.kill_all
        killall_subprocesses
      end

      ok
    end
  end
end
