module NodeCtld::RemoteCommands
  class Update < Base
    handle :update
    needs :subprocess

    def exec
      NodeCtld::Daemon.safe_exit(NodeCtld::EXIT_UPDATE)

      if @force
        NodeCtld::Worker.kill_all
        killall_subprocesses
      end

      ok
    end
  end
end
