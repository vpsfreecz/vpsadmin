module NodeCtld
  class Commands::Dataset::CloneSnapshotName < Commands::Base
    handle 5224

    def exec
      db = Db.new

      rs = db.query("SELECT id, name, created_at FROM snapshots WHERE id IN (#{@snapshots.keys.join(',')})")
      rs.each do |row|
        s = @snapshots[row['id'].to_s]

        db.prepared(
          'UPDATE snapshots SET name = ?, created_at = ? WHERE id = ?',
          row['name'],
          row['created_at'],
          snapshot_clone_id(s)
        )
      end

      db.close
      ok
    end

    def rollback
      db = Db.new

      @snapshots.each_value do |s|
        if s.length >= 3
          db.prepared(
            'UPDATE snapshots SET name = ?, created_at = ? WHERE id = ?',
            s[0],
            s[1],
            snapshot_clone_id(s)
          )
        else
          db.prepared('UPDATE snapshots SET name = ? WHERE id = ?', s[0], snapshot_clone_id(s))
        end
      end

      db.close
      ok
    end

    protected

    def snapshot_clone_id(snapshot_clone)
      snapshot_clone.length >= 3 ? snapshot_clone[2] : snapshot_clone[1]
    end
  end
end
