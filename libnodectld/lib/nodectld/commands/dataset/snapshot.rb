require 'time'

module NodeCtld
  class Commands::Dataset::Snapshot < Commands::Base
    handle 5204
    needs :system, :zfs

    def exec
      @name, @created_at = Dataset.new.snapshot(@pool_fs, @dataset_name)
      ok(
        name: @name,
        created_at: @created_at.iso8601,
      )
    end

    def rollback
      s = @name || get_confirmed_snapshot_name(Db.new, @snapshot_id)
      zfs(:destroy, nil, "#{@pool_fs}/#{@dataset_name}@#{s}", [1])
    end
  end
end
