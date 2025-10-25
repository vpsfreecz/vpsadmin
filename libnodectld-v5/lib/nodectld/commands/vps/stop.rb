module NodeCtld
  class Commands::Vps::Stop < Commands::Base
    handle 1002
    needs :system, :libvirt

    def exec
      conn = LibvirtClient.new
      dom = conn.lookup_domain_by_uuid(@vps_uuid)

      Vps.new(dom, cmd: self).stop(kill: @kill)

      ok
    end

    def rollback
      if @rollback_stop
        conn = LibvirtClient.new
        dom = conn.lookup_domain_by_uuid(@vps_uuid)
        Vps.new(dom, cmd: self).start(autostart_priority: @autostart_priority)
      end

      ok
    end
  end
end
