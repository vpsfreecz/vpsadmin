module NodeCtld::RemoteCommands
  class Stop < Base
    handle :stop
    needs :worker, :subprocess

    def exec
      NodeCtld::Daemon.safe_exit(NodeCtld::EXIT_STOP)

      if @force
        walk_workers { |w| :silent }
        drop_workers
        killall_subprocesses
      end

      ok
    end
  end
end
