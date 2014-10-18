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

    protected
    # Supports only transfer from primary/hypervisor pools to backup pool.
    # Not the other way around.
    def do_transfer(snap1, snap2 = nil)
      ds_name = @branch ? "#{@dataset_name}/#{@branch}" : @dataset_name
      recv = "zfs recv -F #{@dst_pool_fs}/#{ds_name}"

      if snap2
        send = "zfs send -I #{@src_pool_fs}/#{@dataset_name}@#{snap1} #{@src_pool_fs}/#{@dataset_name}@#{snap2}"
      else
        send = "zfs send #{@src_pool_fs}/#{@dataset_name}@#{snap1}"
      end

      syscmd("ssh #{@src_node_addr} #{send} | #{recv}")
    end

    def confirmed_snapshot_name(db, snap)
      return snap['name'] if snap['confirmed']

      st = db.prepared_st('SELECT name FROM snapshots WHERE id = ?', snap['id'])
      ret = st.fetch
      st.close

      ret[0]
    end
  end
end
