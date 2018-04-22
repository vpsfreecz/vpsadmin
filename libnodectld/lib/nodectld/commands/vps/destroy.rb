module NodeCtld
  class Commands::Vps::Destroy < Commands::Base
    handle 3002
    needs :system, :osctl

    def exec
      osctl(%i(ct del), @vps_id)
      ok
    end
  end
end
