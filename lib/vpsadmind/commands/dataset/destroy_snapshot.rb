module VpsAdmind
  class Commands::Dataset::DestroySnapshot < Commands::Base
    handle 5212
    needs :system, :zfs

    def exec
      if @snapshot['confirmed'] == 1
        snapshot = @snapshot['name']
      else
        db = Db.new
        snapshot = get_confirmed_snapshot_name(db, @snapshot['id'])
        db.close
      end

      if @branch
        zfs(:destroy, nil, "#{@pool_fs}/#{@dataset_name}/#{@tree}/#{@branch}@#{snapshot}")

      else
        zfs(:destroy, nil, "#{@pool_fs}/#{@dataset_name}@#{snapshot}")
      end
    end
  end
end
