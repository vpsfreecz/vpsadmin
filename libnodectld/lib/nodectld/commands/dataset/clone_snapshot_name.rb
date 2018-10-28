module NodeCtld
  class Commands::Dataset::CloneSnapshotName < Commands::Base
    handle 5224

    def exec
      db = Db.new

      rs = db.query("SELECT id, name FROM snapshots WHERE id IN (#{@snapshots.keys.join(',')})")
      rs.each do |row|
        s = @snapshots[row['id'].to_s]

        db.prepared('UPDATE snapshots SET name = ? WHERE id = ?', row['name'], s[1])
      end

      db.close
      ok
    end

    def rollback
      db = Db.new

      @snapshots.values.each do |s|
        db.prepared('UPDATE snapshots SET name = ? WHERE id = ?', s[0], s[1])
      end

      db.close
      ok
    end
  end
end
