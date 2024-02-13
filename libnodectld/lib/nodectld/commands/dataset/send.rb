module NodeCtld
  class Commands::Dataset::Send < Commands::Base
    handle 5221
    needs :system, :zfs, :mbuffer

    def exec
      db = Db.new
      snap = confirmed_snapshot_name(db, @snapshots.last)

      from_snap = (confirmed_snapshot_name(db, @snapshots.first) if @snapshots.count > 1)

      db.close

      stream = ZfsStream.new(
        {
          pool: @src_pool_fs,
          tree: @tree,
          branch: @branch,
          dataset: @dataset_name
        },
        snap,
        from_snap
      )

      stream.command(self) do
        stream.send_to(
          @addr,
          @port,
          block_size: $CFG.get(:mbuffer, :send, :block_size),
          buffer_size: $CFG.get(:mbuffer, :send, :buffer_size),
          log_file: mbuffer_log_file,
          timeout: $CFG.get(:mbuffer, :send, :timeout)
        )
      end

      mbuffer_cleanup_log_file

      ok
    end

    def rollback
      ok
    end

    protected

    def confirmed_snapshot_name(db, snap)
      if snapshot_confirmed?(snap)
        snap['name']
      else
        get_confirmed_snapshot_name(db, snap['id'])
      end
    end
  end
end
