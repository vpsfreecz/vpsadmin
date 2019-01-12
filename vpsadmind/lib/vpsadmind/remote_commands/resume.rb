module VpsAdmind::RemoteCommands
  class Resume < Base
    handle :resume

    def exec
      VpsAdmind::Worker.resume
      ok
    end
  end
end
