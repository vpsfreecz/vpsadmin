module NodeCtld
  class Commands::Vps::Destroy < Commands::Base
    handle 3002
    needs :system

    def exec
      conn = LibvirtClient.new

      begin
        dom = conn.lookup_domain_by_uuid(@uuid)
      rescue Libvirt::Error
        # pass
      else
        dom.undefine
      end

      NetAccounting.remove_vps(@vps_id)
      ok
    end
  end
end
