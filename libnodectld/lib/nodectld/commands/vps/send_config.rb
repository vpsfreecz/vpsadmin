module NodeCtld
  class Commands::Vps::SendConfig < Commands::Base
    handle 3030
    needs :system, :osctl, :zfs

    def exec
      send_opts = {
        to_pool: @pool_name,
        as_id: @as_id,
        network_interfaces: @network_interfaces,
        snapshots: @snapshots,
        passphrase: @passphrase
      }

      from_snapshot = from_snapshot_name
      send_opts[:from_snapshot] = from_snapshot if from_snapshot
      send_opts[:preexisting_datasets] = true if @preexisting_datasets

      osctl(
        %i[ct send config],
        [@vps_id, @node],
        send_opts
      )
    end

    def rollback
      osctl(%i[ct send cancel], @vps_id, { force: true, local: true })
    end

    protected

    def from_snapshot_name
      return if @from_snapshot.nil?
      return @from_snapshot unless @from_snapshot.is_a?(Hash)
      return @from_snapshot['name'] if snapshot_confirmed?(@from_snapshot)

      db = Db.new
      get_confirmed_snapshot_name(db, @from_snapshot['id'])
    ensure
      db&.close
    end
  end
end
