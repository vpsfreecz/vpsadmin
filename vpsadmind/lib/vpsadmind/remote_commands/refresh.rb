module VpsAdmind::RemoteCommands
  class Refresh < Base
    handle :refresh

    def exec
      log(:info, :remote, 'Resource update requested')
      @daemon.update_all

      ok
    end
  end
end
