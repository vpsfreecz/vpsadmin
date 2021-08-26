module NodeCtld
  class Commands::Vps::SendConfig < Commands::Base
    handle 3030
    needs :system, :osctl

    def exec
      send_opts = {
        as_id: @as_id,
        network_interfaces: @network_interfaces,
        snapshots: @snapshots,
        passphrase: @passphrase,
      }

      send_opts[:from_snapshot] = @from_snapshot if @from_snapshot
      send_opts[:preexisting_datasets] = true if @preexisting_datasets

      osctl(
        %i(ct send config),
        [@vps_id, @node],
        send_opts,
      )
    end

    def rollback
      osctl(%i(ct send cancel), @vps_id, {force: true, local: true})
    end
  end
end
