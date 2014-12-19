module VpsAdmind
  class Commands::Dataset::Snapshot < Commands::Base
    handle 5204
    needs :system, :zfs

    def exec
      @name = Dataset.new.snapshot(@pool_fs, @dataset_name)
      ok
    end

    def rollback
      s = @name || get_confirmed_snapshot_name(Db.new, @snapshot_id)
      zfs(:destroy, nil, "#{@pool_fs}/#{@dataset_name}@#{s}", [1])
    end

    def post_save(db)
      db.prepared('UPDATE snapshots SET name = ? WHERE id = ?', @name, @snapshot_id)
    end
  end
end
