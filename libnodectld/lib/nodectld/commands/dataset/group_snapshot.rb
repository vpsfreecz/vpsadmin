require 'time'

module NodeCtld
  class Commands::Dataset::GroupSnapshot < Commands::Base
    handle 5215

    include Utils::System
    include Utils::Zfs

    def exec
      return strict_exec if strict_receipt

      @name = nil
      @created_at = nil

      # In case nodectld has crashed while saving the result of the transaction,
      # recover it from the state file and do not create new snapshots.
      if has_saved_state?
        log(:work, self, 'Found pre-crash group snapshot state')
        restore_state

        # Check that the snapshots actually exist
        return ok if @snapshots.empty?

        first_snap = @snapshots.first

        begin
          zfs(:list, '-H -o name', "#{first_snap['pool_fs']}/#{first_snap['dataset_name']}@#{@name}")
        rescue SystemCommandFailed
          log(:work, self, 'Pre-crash snapshot not found, disregarding old state')
          @name = nil
          @created_at = nil
        else
          log(:work, self, 'Reusing pre-crash group snapshot state')
          return ok
        end
      end

      # Create new snapshots
      t = Time.now.utc
      @created_at ||= t.strftime('%Y-%m-%d %H:%M:%S')
      @name ||= t.strftime('%Y-%m-%dT%H:%M:%S')

      zfs(
        :snapshot,
        nil,
        snapshot_paths.join(' ')
      )

      save_state

      ok
    end

    def rollback
      return strict_rollback if strict_receipt

      @snapshots.each do |s|
        zfs(:destroy, nil, "#{s['pool_fs']}/#{s['dataset_name']}@#{@name}", valid_rcs: [1])
      end

      ok
    end

    def on_save(db)
      db.prepared(
        "UPDATE snapshots SET name = ?, created_at = ? WHERE id IN (#{@snapshots.map { '?' }.join(',')})",
        @name,
        @created_at,
        *@snapshots.map { |snap| snap['snapshot_id'] }
      )
    end

    def post_save
      remove_state unless strict_receipt
    end

    def storage_observation(direction)
      if direction == :execute
        [@execute_before, @execute_after]
      else
        [@rollback_before, @rollback_after]
      end
    end

    def capture_interrupted_execute_observation
      return unless strict_receipt && @execute_before

      @execute_after = strict_receipt.observe_all! if @execute_after.nil?
    end

    protected

    def strict_receipt
      @command.strict_group_snapshot_receipt if @command.respond_to?(:strict_group_snapshot_receipt)
    end

    def strict_exec
      @name = @planned_snapshot_name
      @created_at = Time.strptime(@name, '%Y-%m-%dT%H:%M:%S').utc.strftime('%Y-%m-%d %H:%M:%S')
      @execute_before = strict_receipt.before
      zfs(:snapshot, nil, snapshot_paths.join(' '))
      @execute_after = strict_receipt.observe_all!
      raise 'group snapshot postflight is incomplete' unless
        @execute_before.zip(@execute_after).all? do |prior, current|
          StorageGroupSnapshotReceipt.created?(prior, current)
        end

      ok
    ensure
      if strict_receipt && @execute_before && @execute_after.nil?
        @execute_after = strict_receipt.observe_all!
      end
    end

    def strict_rollback
      @name = @planned_snapshot_name
      receipt = strict_receipt
      @rollback_before = receipt.before
      receipt.targets.zip(receipt.created_guids, @rollback_before).each do |target, guid, current|
        next unless guid

        latest = receipt.observe_target!(target)
        raise 'group rollback identity changed' unless
          latest == current && latest[:presence] == :present && latest[:guid] == guid &&
          latest[:path] == target[:path] && latest[:owner_guid] == target[:owner_guid] &&
          latest[:empty_dependencies]

        zfs(:destroy, nil, target[:path])
      end
      @rollback_after = receipt.observe_all!
      raise 'group rollback postflight is incomplete' unless
        @rollback_before.zip(@rollback_after, receipt.created_guids).all? do |prior, current, guid|
          guid ? StorageGroupSnapshotReceipt.compensated?(prior, current) : prior == current
        end

      ok
    ensure
      @rollback_after ||= receipt.observe_all! if receipt && @rollback_before
    end

    def snapshot_paths
      @snapshots.map { |s| "#{s['pool_fs']}/#{s['dataset_name']}@#{@name}" }
    end

    def save_state
      File.open(state_file_path, 'w') do |f|
        f.puts({
          name: @name,
          created_at: @created_at
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
      # ignore
    end

    def has_saved_state?
      File.exist?(state_file_path)
    end

    def state_file_path
      @state_file_path ||= File.join(
        RemoteControl::RUNDIR,
        ".transaction-#{@command.id}-group-snapshot.json"
      )
    end
  end
end
