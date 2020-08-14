module NodeCtld
  class Commands::Vps::UnmanageDnsResolver < Commands::Base
    handle 2027
    needs :system, :osctl

    def exec
      osctl(%i(ct unset dns-resolver), @vps_id)
      ok
    end

    def rollback
      osctl(%i(ct set dns-resolver), [@vps_id] + @original)
      ok
    end
  end
end
