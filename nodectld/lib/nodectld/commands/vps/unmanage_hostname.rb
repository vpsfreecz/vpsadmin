module NodeCtld
  class Commands::Vps::UnmanageHostname < Commands::Base
    handle 2016
    needs :system, :osctl

    def exec
      osctl(%i(ct unset hostname), @vps_id)
    end

    def rollback
      osctl(%i(ct set hostname), [@vps_id, @hostname])
    end
  end
end
