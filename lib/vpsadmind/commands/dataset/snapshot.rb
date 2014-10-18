module VpsAdmind
  class Commands::Dataset::Snapshot < Commands::Base
    handle 5204

    def exec
      @name = Dataset.new.snapshot(@pool_fs, @dataset_name)
      ok
    end

    def post_save(db)
      db.prepared('UPDATE snapshots SET name = ? WHERE id = ?', @name, @snapshot_id)
    end
  end
end
