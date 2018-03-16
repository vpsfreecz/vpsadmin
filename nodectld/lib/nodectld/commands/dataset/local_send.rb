module NodeCtld
  class Commands::Dataset::LocalSend < Commands::Base
    handle 5223
    needs :system, :zfs

    def exec
      db = Db.new

      snap = confirmed_snapshot_name(db, @snapshots.last)
      from_snap = @snapshots.count > 1 ? confirmed_snapshot_name(db, @snapshots.first) : nil

      db.close

      stream = ZfsStream.new(
          {
              pool: @src_pool_fs,
              tree: @src_tree,
              branch: @src_branch,
              dataset: @src_dataset_name,
          },
          snap,
          from_snap
      )

      stream.command(self) do
        stream.send_recv({
            pool: @dst_pool_fs,
            tree: @dst_tree,
            branch: @dst_branch,
            dataset: @dst_dataset_name,
        })
      end

      ok
    end

    def rollback
      db = Db.new
      ds_name = @dst_branch ? "#{@dst_dataset_name}/#{@dst_tree}/#{@dst_branch}" : @dst_dataset_name

      @snapshots.reverse_each do |s|
        zfs(:destroy, nil, "#{@dst_pool_fs}/#{ds_name}@#{confirmed_snapshot_name(db, s)}", [1])
      end

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
