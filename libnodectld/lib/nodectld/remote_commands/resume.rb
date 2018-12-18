module NodeCtld::RemoteCommands
  class Resume < Base
    handle :resume

    def exec
      NodeCtld::Worker.resume
      ok
    end
  end
end
