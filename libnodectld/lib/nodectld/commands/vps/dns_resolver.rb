module NodeCtld
  class Commands::Vps::DnsResolver < Commands::Base
    handle 2005
    needs :system, :osctl

    def exec
      osctl(%i(ct set dns-resolver), [@vps_id] + @nameserver)
      ok
    end

    def rollback
      osctl(%i(ct set dns-resolver), [@vps_id] + @original)
      ok
    end
  end
end
