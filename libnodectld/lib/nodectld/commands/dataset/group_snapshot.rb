module NodeCtld
  class Commands::Dataset::GroupSnapshot < Commands::Base
    handle 5215

    include Utils::System
    include Utils::Zfs

    def exec
      # In case nodectld has crashed while saving the result of the transaction,
      # recover it from the state file and do not create new snapshots.
      if has_saved_state?
        log(:work, self, 'Found pre-crash group snapshot state')
        restore_state

        # Check that the snapshots actually exist
        return ok if @snapshots.empty?

        s = @snapshots.first

        begin
          zfs(:list, '-H -o name', "#{s['pool_fs']}/#{s['dataset_name']}@#{@name}")
        rescue SystemCommandFailed
          log(:work, self, 'Pre-crash snapshot not found, disregarding old state')
        else
          log(:work, self, 'Reusing pre-crash group snapshot state')
          return ok
        end
      end

      # Create new snapshots
      t = Time.now.utc
      @created_at = t.strftime('%Y-%m-%d %H:%M:%S')
      @name = t.strftime('%Y-%m-%dT%H:%M:%S')

      zfs(
        :snapshot,
        nil,
        @snapshots.inject([]) do |snaps, s|
          snaps << "#{s['pool_fs']}/#{s['dataset_name']}@#{@name}"
        end.join(' ')
      )

      save_state

      ok
    end

    def rollback
      @snapshots.each do |s|
        zfs(:destroy, nil, "#{s['pool_fs']}/#{s['dataset_name']}@#{@name}", [1])
      end

      ok
    end

    def on_save(db)
      @snapshots.each do |snap|
        db.prepared(
          'UPDATE snapshots SET name = ?, created_at = ? WHERE id = ?',
          @name,
          @created_at,
          snap['snapshot_id']
        )
      end
    end

    def post_save
      remove_state
    end

    protected
    def save_state
      File.open(state_file_path, 'w') do |f|
        f.puts({
          name: @name,
          created_at: @created_at,
        }.to_json)
      end
    end

    def restore_state
      state = JSON.parse(File.read(state_file_path))

      @name = state['name']
      @created_at = state['created_at']
    end

    def remove_state
      File.unlink(state_file_path)
    rescue Errno::ENOENT
    end

    def has_saved_state?
      File.exist?(state_file_path)
    end

    def state_file_path
      @state_file_path ||= File.join(
        RemoteControl::RUNDIR,
        ".transaction-#{@command.id}-group-snapshot.json",
      )
    end
  end
end
