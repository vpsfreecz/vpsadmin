module NodeCtld
  class Commands::Vps::SendConfig < Commands::Base
    handle 3030
    needs :system, :osctl

    def exec
      osctl(
        %i(ct send config),
        [@vps_id, @node],
        {
          as_id: @as_id,
          network_interfaces: @network_interfaces,
          snapshots: @snapshots,
          passphrase: @passphrase,
        }
      )
    end

    def rollback
      osctl(%i(ct send cancel), @vps_id, {force: true, local: true})
    end
  end
end
