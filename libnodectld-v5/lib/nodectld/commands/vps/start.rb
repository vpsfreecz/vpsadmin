module NodeCtld
  class Commands::Vps::Start < Commands::Base
    handle 1001

    def exec
      conn = LibvirtClient.new
      dom = conn.lookup_domain_by_uuid(@vps_uuid)
      dom.create
      ok
    end

    def rollback
      if @rollback_start
        conn = LibvirtClient.new
        dom = conn.lookup_domain_by_uuid(@vps_uuid)

        begin
          dom.destroy # TODO: graceful shutdown
        rescue Libvirt::Error
          # pass
        end
      end

      ok
    end
  end
end
