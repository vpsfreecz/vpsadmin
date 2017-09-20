module VpsAdmind::RemoteCommands
  class Resume < Base
    handle :resume

    def exec
      @daemon.resume
      ok
    end
  end
end
