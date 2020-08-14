module NodeCtld
  class Commands::Vps::DnsResolver < Commands::Base
    handle 2005
    needs :system, :osctl

    def exec
      osctl(%i(ct set dns-resolver), [@vps_id] + @nameserver)
      ok
    end

    def rollback
      if @original
        osctl(%i(ct set dns-resolver), [@vps_id] + @original)
      else
        osctl(%i(ct unset dns-resolver), @vps_id)
      end
      ok
    end
  end
end
