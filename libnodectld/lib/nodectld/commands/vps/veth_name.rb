module NodeCtld
  class Commands::Vps::VethName < Commands::Base
    handle 2020
    needs :system, :osctl, :vps

    def exec
      honor_state do
        osctl(%i(ct stop), @vps_id)
        osctl(%i(ct netif rename), [@vps_id, @original, @veth_name])
      end

      ok
    end

    def rollback
      honor_state do
        osctl(%i(ct stop), @vps_id)
        osctl(%i(ct netif rename), [@vps_id, @veth_name, @original])
      end

      ok
    end
  end
end
