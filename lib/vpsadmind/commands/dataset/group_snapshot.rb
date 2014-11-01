module VpsAdmind
  class Commands::Dataset::GroupSnapshot < Commands::Base
    handle 5215

    include Utils::System
    include Utils::Zfs

    def exec
      @name = Time.new.strftime('%Y-%m-%dT%H:%M:%S')

      zfs(
          :snapshot,
          nil,
          @snapshots.inject([]) { |snaps, s| snaps << "#{s['pool_fs']}/#{s['dataset_name']}@#{@name}" }.join(' ')
      )
    end

    def post_save(db)
      @snapshots.each do |snap|
        db.prepared('UPDATE snapshots SET name = ? WHERE id = ?', @name, snap['snapshot_id'])
      end
    end
  end
end
