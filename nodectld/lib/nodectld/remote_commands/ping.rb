module NodeCtld::RemoteCommands
  class Ping < Base
    handle :ping

    def exec
      ok.update({:output => {:pong => :pong}})
    end
  end
end
