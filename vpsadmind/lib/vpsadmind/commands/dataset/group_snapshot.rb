module VpsAdmind
  class Commands::Dataset::GroupSnapshot < Commands::Base
    handle 5215

    include Utils::System
    include Utils::Zfs

    def exec
      @created_at = Time.now.utc
      @name = @created_at.strftime('%Y-%m-%dT%H:%M:%S')

      zfs(
          :snapshot,
          nil,
          @snapshots.inject([]) { |snaps, s| snaps << "#{s['pool_fs']}/#{s['dataset_name']}@#{@name}" }.join(' ')
      )
    end

    def rollback
      @snapshots.each do |s|
        zfs(:destroy, nil, "#{s['pool_fs']}/#{s['dataset_name']}@#{@name}", [1])
      end

      ok
    end

    def post_save(db)
      @snapshots.each do |snap|
        db.prepared(
            'UPDATE snapshots SET name = ?, created_at = ? WHERE id = ?',
            @name,
            @created_at,
            snap['snapshot_id']
        )
      end
    end
  end
end
