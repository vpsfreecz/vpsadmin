module VpsAdmind
  class Commands::Dataset::Snapshot < Commands::Base
    handle 5204
    needs :system, :zfs

    def exec
      @name, @created_at = Dataset.new.snapshot(@pool_fs, @dataset_name)
      ok
    end

    def rollback
      s = @name || get_confirmed_snapshot_name(Db.new, @snapshot_id)
      zfs(:destroy, nil, "#{@pool_fs}/#{@dataset_name}@#{s}", [1])
    end

    def post_save(db)
      db.prepared(
          'UPDATE snapshots SET name = ?, created_at = ? WHERE id = ?',
          @name,
          @created_at.strftime('%Y-%m-%d %H:%M:%S'),
          @snapshot_id
      )
    end
  end
end
