module NodeCtld
  class Commands::NetworkInterface::Rename < Commands::Base
    handle 2020
    needs :system, :osctl, :vps

    def exec
      honor_state do
        osctl(%i(ct stop), @vps_id)
        osctl(%i(ct netif rename), [@vps_id, @original, @name])
      end

      VpsConfig.edit(@pool_fs, @vps_id) do |cfg|
        cfg.network_interfaces.rename(@original, @name)
      end

      ok
    end

    def rollback
      honor_state do
        osctl(%i(ct stop), @vps_id)
        osctl(%i(ct netif rename), [@vps_id, @name, @original])
      end

      VpsConfig.edit(@pool_fs, @vps_id) do |cfg|
        cfg.network_interfaces.rename(@name, @original)
      end

      ok
    end
  end
end
