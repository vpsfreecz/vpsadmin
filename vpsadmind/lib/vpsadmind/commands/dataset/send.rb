module VpsAdmind
  class Commands::Dataset::Send < Commands::Base
    handle 5221
    needs :system, :zfs

    def exec
      db = Db.new

      snap = confirmed_snapshot_name(db, @snapshots.last)
      from_snap = @snapshots.count > 1 ? confirmed_snapshot_name(db, @snapshots.first) : nil

      db.close

      stream = ZfsStream.new(
          {
              pool: @src_pool_fs,
              tree: @tree,
              branch: @branch,
              dataset: @dataset_name,
          },
          snap,
          from_snap,
      )

      stream.command(self) do
        stream.send_to(
            @addr,
            port: @port,
        )
      end

      ok
    end

    def rollback
      ok
    end

    protected
    def confirmed_snapshot_name(db, snap)
      if snap['confirmed'] == 1
        snap['name']
      else
        get_confirmed_snapshot_name(db, snap['id'])
      end
    end
  end
end
