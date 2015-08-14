module VpsAdmind
  class Commands::Dataset::Recv < Commands::Base
    handle 5220
    needs :system, :zfs, :subprocess

    def exec
      ds_name = @branch ? "#{@dataset_name}/#{@tree}/#{@branch}" : @dataset_name
      recv = "zfs recv -F #{@dst_pool_fs}/#{ds_name}"
      cmd = "nc -d -l #{@addr} #{@port} | #{recv}"

      log(:work, self, "fork #{cmd}")

      blocking_fork do
        # It is imperative to use Process.exec here. Otherwise the daemon
        # is disturbed when the child process finishes.
        # The problem is that the child process shares the socket to database
        # and when it finishes, the socket is closed, which kicks out the daemon
        # as well. There may be other hiccups.
        Process.exec(cmd)
      end

      ok
    end

    def rollback
      db = Db.new
      ds_name = @branch ? "#{@dataset_name}/#{@tree}/#{@branch}" : @dataset_name

      @snapshots.reverse_each do |s|
        zfs(:destroy, nil, "#{@dst_pool_fs}/#{ds_name}@#{confirmed_snapshot_name(db, s)}", [1])
      end

      # Kill nc - just connect and close
      begin
        s = TCPSocket.new(@addr, @port)
        s.close

      rescue Errno::ECONNREFUSED

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
