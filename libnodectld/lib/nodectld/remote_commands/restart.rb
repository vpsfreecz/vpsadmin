module NodeCtld::RemoteCommands
  class Restart < Base
    handle :restart
    needs :subprocess

    def exec
      NodeCtld::Daemon.safe_exit(NodeCtld::EXIT_RESTART)

      if @force
        NodeCtld::Worker.kill_all
        killall_subprocesses
      end

      ok
    end
  end
end
