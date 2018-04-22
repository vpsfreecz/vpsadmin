module NodeCtld::RemoteCommands
  class Update < Base
    handle :update
    needs :worker, :subprocess

    def exec
      NodeCtld::Daemon.safe_exit(NodeCtld::EXIT_UPDATE)

      if @force
        walk_workers { |w| :silent }
        drop_workers
        killall_subprocesses
      end

      ok
    end
  end
end
