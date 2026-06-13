module NodeCtld
  class Commands::Vps::Copy < Commands::Base
    handle 3040
    needs :system, :osctl, :zfs

    def exec
      copy_opts = {
        pool: @as_pool_name,
        dataset: @as_dataset,
        consistent: @consistent,
        network_interfaces: @network_interfaces
      }
      from_snapshot = from_snapshot_name
      copy_opts[:from_snapshot] = from_snapshot if from_snapshot

      osctl(
        %i[ct cp],
        [@vps_id, @as_id],
        copy_opts
      )
    end

    def rollback
      osctl_pool(@as_pool_name, %i[ct del], @as_id, { force: true }, {}, valid_rcs: [1])
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
