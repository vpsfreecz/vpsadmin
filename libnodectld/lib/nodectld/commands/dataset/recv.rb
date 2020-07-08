module NodeCtld
  class Commands::Dataset::Recv < Commands::Base
    handle 5220
    needs :system, :zfs, :subprocess

    def exec
      ds_name = @branch ? "#{@dataset_name}/#{@tree}/#{@branch}" : @dataset_name
      recv = "zfs recv -F -u #{@dst_pool_fs}/#{ds_name}"
      cmd = "socat -u -T 3600 TCP4-LISTEN:#{@port},bind=#{@addr} - | #{recv}"

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
      # Kill nc - just connect and close.
      # This will not stop an ongoing transfer.
      begin
        s = TCPSocket.new(@addr, @port)
        s.close

      rescue Errno::ECONNREFUSED

      end

      # Remove received snapshots
      db = Db.new
      ds_name = @branch ? "#{@dataset_name}/#{@tree}/#{@branch}" : @dataset_name

      # If there are more than 1 snapshots, it means that it is incremental transfer.
      # The first snapshot MUST NOT be deleted as it would break history flow.
      # The first snapshot is not a part of the transfer anyway, it is already present
      # and is just a common point in history.
      snaps = if @snapshots.size > 1
                @snapshots[1..-1]
              else
                @snapshots
              end

      snaps.reverse_each do |s|
        zfs(
          :destroy,
          nil,
          "#{@dst_pool_fs}/#{ds_name}@#{confirmed_snapshot_name(db, s)}",
          valid_rcs: [1]
        )
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
