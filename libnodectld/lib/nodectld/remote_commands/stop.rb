module NodeCtld::RemoteCommands
  class Stop < Base
    handle :stop
    needs :subprocess

    def exec
      NodeCtld::Daemon.safe_exit(NodeCtld::EXIT_STOP)

      if @force
        NodeCtld::Worker.kill_all
        killall_subprocesses
      end

      ok
    end
  end
end
