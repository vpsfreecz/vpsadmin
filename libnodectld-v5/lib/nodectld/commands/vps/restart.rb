module NodeCtld
  class Commands::Vps::Restart < Commands::Base
    handle 1003

    def exec
      conn = LibvirtClient.new
      dom = conn.lookup_domain_by_uuid(@vps_uuid)

      Vps.new(dom, cmd: self).restart(autostart_priority: @autostart_priority)

      ok
    end

    def rollback
      ok
    end
  end
end
