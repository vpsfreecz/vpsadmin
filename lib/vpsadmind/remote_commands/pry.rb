module VpsAdmind::RemoteCommands
  class Pry < Base
    handle :pry

    def exec
      binding.remote_pry
      ok
    end
  end
end
