module NodeCtld
  class Commands::Vps::Restart < Commands::Base
    handle 1003

    def exec
      conn = LibvirtClient.new
      dom = conn.lookup_domain_by_uuid(@vps_uuid)

      begin
        dom.destroy # TODO: graceful shutdown
      rescue Libvirt::Error
        # pass
      end

      dom.create

      ok
    end

    def rollback
      ok
    end
  end
end
