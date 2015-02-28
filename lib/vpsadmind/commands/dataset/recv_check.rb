module VpsAdmind
  class Commands::Dataset::RecvCheck < Commands::Base
    handle 5222
    needs :system, :zfs

    def exec
      ds_name = @branch ? "#{@dataset_name}/#{@tree}/#{@branch}" : @dataset_name

      if @snapshot['confirmed'] == 1
        snapshot = @snapshot['name']
      else
        db = Db.new
        snapshot = get_confirmed_snapshot_name(db, @snapshot['id'])
        db.close
      end

      zfs(:get, '-H -ovalue name', "#{@dst_pool_fs}/#{ds_name}@#{snapshot}")
    end

    def rollback
      ok
    end
  end
end
