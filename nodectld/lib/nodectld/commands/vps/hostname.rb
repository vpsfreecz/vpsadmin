module NodeCtld
  class Commands::Vps::Hostname < Commands::Base
    handle 2004
    needs :system, :osctl

    def exec
      osctl(%i(ct set hostname), [@vps_id, @hostname])
    end

    def rollback
      osctl(%i(ct set hostname), [@vps_id, @original])
    end
  end
end
