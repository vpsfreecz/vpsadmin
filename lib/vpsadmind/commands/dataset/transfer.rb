module VpsAdmind
  class Commands::Dataset::Transfer < Commands::Base
    handle 5205

    include Utils::System
    include Utils::Zfs

    def exec
      db = Db.new

      snap1 = confirmed_snapshot_name(db, @snapshots.first)
      snap2 = @snapshots.count > 1 ? confirmed_snapshot_name(db, @snapshots.last) : nil

      db.close

      do_transfer(snap1) if @initial
      do_transfer(snap1, snap2) if snap2

      ok
    end

    def rollback
      db = Db.new
      ds_name = @branch ? "#{@dataset_name}/#{@tree}/#{@branch}" : @dataset_name

      @snapshots.reverse_each do |s|
        zfs(:destroy, nil, "#{@dst_pool_fs}/#{ds_name}@#{confirmed_snapshot_name(db, s)}", [1])
      end

      ok
    end

    protected
    # Supports only transfer from primary/hypervisor pools to backup pool.
    # Not the other way around.
    def do_transfer(snap1, snap2 = nil)
      ds_name = @branch ? "#{@dataset_name}/#{@tree}/#{@branch}" : @dataset_name
      recv = "zfs recv -F #{@dst_pool_fs}/#{ds_name}"

      if snap2
        send = "zfs send -I #{@src_pool_fs}/#{@dataset_name}@#{snap1} #{@src_pool_fs}/#{@dataset_name}@#{snap2}"
      else
        send = "zfs send #{@src_pool_fs}/#{@dataset_name}@#{snap1}"
      end

      syscmd("ssh #{@src_node_addr} #{send} | #{recv}")
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
