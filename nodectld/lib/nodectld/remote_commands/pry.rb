module NodeCtld::RemoteCommands
  class Pry < Base
    handle :pry

    def exec
      binding.remote_pry
      ok

    rescue DRb::DRbConnError
      ok
    end
  end
end
