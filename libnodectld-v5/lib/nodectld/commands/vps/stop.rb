module NodeCtld
  class Commands::Vps::Stop < Commands::Base
    handle 1002
    needs :system

    def exec
      conn = LibvirtClient.new
      dom = conn.lookup_domain_by_uuid(@vps_uuid)

      begin
        dom.destroy # TODO: graceful shutdown
      rescue Libvirt::Error
        # pass
      end

      ok
    end

    def rollback
      if @rollback_stop
        conn = LibvirtClient.new
        dom = conn.lookup_domain_by_uuid(@vps_uuid)
        dom.create
      end

      ok
    end
  end
end
