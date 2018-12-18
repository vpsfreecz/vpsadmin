module NodeCtld::RemoteCommands
  class Pause < Base
    handle :pause

    def exec
      ::NodeCtld::Worker.pause
      ok
    end
  end
end
