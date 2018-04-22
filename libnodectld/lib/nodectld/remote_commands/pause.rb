module NodeCtld::RemoteCommands
  class Pause < Base
    handle :pause

    def exec
      @daemon.pause(@t_id || true)
      ok
    end
  end
end
