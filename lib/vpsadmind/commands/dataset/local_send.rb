module VpsAdmind
  class Commands::Dataset::LocalSend < Commands::Base
    handle 5223
    needs :system, :zfs

    def exec
      db = Db.new

      snap1 = confirmed_snapshot_name(db, @snapshots.first)
      snap2 = @snapshots.count > 1 ? confirmed_snapshot_name(db, @snapshots.last) : nil

      db.close
      do_transfer(snap1, snap2)

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
    # Supports only transfer from primary/hypervisor pools to backup pool.
    # Not the other way around.
    def do_transfer(snap1, snap2 = nil)
      src_ds_name = @src_branch ? "#{@src_dataset_name}/#{@src_tree}/#{@src_branch}" : @src_dataset_name
      dst_ds_name = @dst_branch ? "#{@dst_dataset_name}/#{@dst_tree}/#{@dst_branch}" : @dst_dataset_name

      if snap2
        send = "zfs send -I #{@src_pool_fs}/#{src_ds_name}@#{snap1} #{@src_pool_fs}/#{src_ds_name}@#{snap2}"
      else
        send = "zfs send #{@src_pool_fs}/#{src_ds_name}@#{snap1}"
      end

      recv = "zfs recv -F #{@dst_pool_fs}/#{dst_ds_name}"

      pipeline_r(send, recv)
    end

    def confirmed_snapshot_name(db, snap)
      if snap['confirmed'] == 1
        snap['name']
      else
        get_confirmed_snapshot_name(db, snap['id'])
      end
    end
  end
end
