module VpsAdmind
  class Commands::Dataset::Send < Commands::Base
    handle 5221
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
      ok
    end

    protected
    # Supports only transfer from primary/hypervisor pools to backup pool.
    # Not the other way around.
    def do_transfer(snap1, snap2 = nil)
      ds_name = @branch ? "#{@dataset_name}/#{@tree}/#{@branch}" : @dataset_name

      if snap2
        send = "zfs send -I #{@src_pool_fs}/#{ds_name}@#{snap1} #{@src_pool_fs}/#{ds_name}@#{snap2}"
      else
        send = "zfs send #{@src_pool_fs}/#{ds_name}@#{snap1}"
      end

      pipeline_r(send, "nc #{@addr} #{@port}")
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
