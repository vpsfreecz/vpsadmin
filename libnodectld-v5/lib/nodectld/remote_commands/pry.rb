require 'pry-remote'

module NodeCtld::RemoteCommands
  class Pry < Base
    handle :pry

    def exec
      binding.remote_pry # rubocop:disable Lint/Debugger
      ok
    rescue DRb::DRbConnError
      ok
    end
  end
end
