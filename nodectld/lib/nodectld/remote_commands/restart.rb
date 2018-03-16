module NodeCtld::RemoteCommands
  class Restart < Base
    handle :restart
    needs :worker, :subprocess

    def exec
      NodeCtld::Daemon.safe_exit(NodeCtld::EXIT_RESTART)

      if @force
        walk_workers { |w| :silent }
        drop_workers
        killall_subprocesses
      end

      ok
    end
  end
end
