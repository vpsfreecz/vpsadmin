module VpsAdmind::RemoteCommands
  class Update < Base
    handle :update
    needs :worker

    def exec
      VpsAdmind::Daemon.safe_exit(VpsAdmind::EXIT_UPDATE)

      if @force
        walk_workers { |w| :silent }
        drop_workers
      end

      ok
    end
  end
end
