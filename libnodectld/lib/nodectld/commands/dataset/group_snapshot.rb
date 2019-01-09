require 'time'

module NodeCtld
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
        @snapshots.inject([]) do |snaps, s|
          snaps << "#{s['pool_fs']}/#{s['dataset_name']}@#{@name}"
        end.join(' ')
      )

      ok(
        name: @name,
        created_at: @created_at.iso8601,
      )
    end

    def rollback
      @snapshots.each do |s|
        zfs(:destroy, nil, "#{s['pool_fs']}/#{s['dataset_name']}@#{@name}", [1])
      end

      ok
    end
  end
end
