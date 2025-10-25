module NodeCtld
  class Commands::Vps::Start < Commands::Base
    handle 1001

    def exec
      conn = LibvirtClient.new
      dom = conn.lookup_domain_by_uuid(@vps_uuid)
      Vps.new(dom, cmd: self).start(autostart_priority: @autostart_priority)
      ok
    end

    def rollback
      if @rollback_start
        conn = LibvirtClient.new
        dom = conn.lookup_domain_by_uuid(@vps_uuid)

        Vps.new(dom, cmd: self).stop
      end

      ok
    end
  end
end
