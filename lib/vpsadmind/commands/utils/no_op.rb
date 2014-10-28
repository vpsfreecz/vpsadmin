module VpsAdmind
  class Commands::Utils::NoOp < Commands::Base
    handle 10001

    def exec
      ok
    end
  end
end
