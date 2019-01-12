module VpsAdmind::RemoteCommands
  class Pause < Base
    handle :pause

    def exec
      VpsAdmind::Worker.pause
      ok
    end
  end
end
