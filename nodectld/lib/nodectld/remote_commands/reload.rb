module NodeCtld::RemoteCommands
  class Reload < Base
    handle :reload

    def exec
      log 'Reloading config'
      $CFG.reload
      ok
    end
  end
end
