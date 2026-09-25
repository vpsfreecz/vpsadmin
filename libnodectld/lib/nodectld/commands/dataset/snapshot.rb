require 'digest'

module NodeCtld
  class Commands::Dataset::Snapshot < Commands::Base
    handle 5204
    needs :system, :zfs

    def exec
      if guarded?
        @name = @planned_snapshot_name
        check_target!
        @execute_before = observe_snapshot
        unless @execute_before[:presence] == :missing
          raise 'snapshot preflight is not proven missing; reconcile before retry'
        end

        @name, @created_at = Dataset.new.snapshot(@pool_fs, @dataset_name, name: @name)
        @execute_after = observe_snapshot
        unless created_by_this_attempt?(@execute_before, @execute_after)
          raise 'snapshot postflight identity is incomplete'
        end

        @created_identity = identity(@execute_after)
      else
        @name, @created_at = Dataset.new.snapshot(@pool_fs, @dataset_name)
      end
      ok
    ensure
      @execute_after ||= observe_snapshot if guarded? && @execute_before
      @created_identity ||= identity(@execute_after) if created_by_this_attempt?(
        @execute_before, @execute_after
      )
    end

    def rollback
      if guarded?
        @name ||= @planned_snapshot_name
        check_target!
        @rollback_before = observe_snapshot
        if @execute_before && @execute_before[:presence] == :present
          unless @execute_after == @execute_before && @rollback_before == @execute_before
            raise 'preexisting snapshot changed after rejected create'
          end

          @rollback_after = @rollback_before
          return ok
        end

        if @execute_before && @execute_before[:presence] == :missing &&
           @execute_after == @execute_before && @rollback_before == @execute_before
          @rollback_after = @rollback_before
          return ok
        end

        expected = @created_identity || @command.successful_snapshot_execute_identity
        unless expected && @rollback_before[:presence] == :present &&
               identity(@rollback_before) == expected
          raise 'snapshot identity is not bound to this attempt'
        end

        zfs(:destroy, nil, snapshot_path)
        @rollback_after = observe_snapshot
        unless @rollback_after[:presence] == :missing &&
               @rollback_after[:owner_guid] == expected[:owner_guid] &&
               @rollback_after[:path] == snapshot_path
          raise 'snapshot rollback postflight identity is incomplete'
        end

        return ok
      end

      s = @name || get_confirmed_snapshot_name(Db.new, @snapshot_id)
      zfs(:destroy, nil, "#{@pool_fs}/#{@dataset_name}@#{s}", valid_rcs: [1])
    ensure
      @rollback_after ||= observe_snapshot if guarded? && @rollback_before
    end

    def on_save(db)
      db.prepared(
        'UPDATE snapshots SET name = ?, created_at = ? WHERE id = ?',
        @name,
        @created_at.strftime('%Y-%m-%d %H:%M:%S'),
        @snapshot_id
      )
    end

    def storage_observation(direction)
      if direction == :execute
        [@execute_before, @execute_after]
      else
        [@rollback_before, @rollback_after]
      end
    end

    def capture_interrupted_execute_observation
      return unless guarded? && @execute_before

      @execute_after ||= observe_snapshot
      @created_identity ||= identity(@execute_after) if created_by_this_attempt?(
        @execute_before, @execute_after
      )
    end

    private

    def guarded?
      return false unless @storage_guard.is_a?(Hash)

      unless @planned_snapshot_name.to_s.match?(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\z/)
        raise 'guarded snapshot has an invalid planned name'
      end

      true
    end

    def snapshot_path
      "#{@pool_fs}/#{@dataset_name}@#{@name}"
    end

    def check_target!
      target = @command.storage_snapshot_target
      raise 'guarded snapshot target path does not match command' unless target &&
                                                                         target.expected_path == snapshot_path
    end

    def created_by_this_attempt?(before, after)
      before && after && before[:presence] == :missing && after[:presence] == :present &&
        before[:path] == after[:path] && before[:owner_guid] == after[:owner_guid] &&
        after[:guid]
    end

    def identity(observation)
      return unless observation && observation[:presence] == :present

      { guid: observation[:guid], owner_guid: observation[:owner_guid],
        path_digest: Digest::SHA256.hexdigest(observation[:path]) }
    end

    def observe_snapshot
      owner_path = "#{@pool_fs}/#{@dataset_name}"
      listing = zfs(:list, '-H -t all -r -o name,guid', owner_path)
      raise 'snapshot inventory is too large' if listing.output.bytesize > 32 * 1024 * 1024

      rows = listing.output.lines.map { |line| line.strip.split("\t", 2) }
      malformed = rows.any? do |name, guid|
        name.to_s.empty? || !guid.to_s.match?(/\A\d+\z/)
      end
      raise 'snapshot inventory has malformed rows' if malformed

      owner_rows = rows.select { |name, _guid| name == owner_path }
      snapshot_rows = rows.select { |name, _guid| name == snapshot_path }
      raise 'snapshot inventory has no unique owner' unless owner_rows.length == 1
      raise 'snapshot inventory has duplicate target' if snapshot_rows.length > 1

      owner_guid = owner_rows.first.last
      if @command.storage_snapshot_target.expected_owner_guid &&
         owner_guid != @command.storage_snapshot_target.expected_owner_guid
        raise 'snapshot owner GUID differs from planned target'
      end

      if snapshot_rows.empty?
        { presence: :missing, path: snapshot_path, owner_guid: }
      else
        { presence: :present, path: snapshot_path,
          guid: snapshot_rows.first.last, owner_guid: }
      end
    rescue StandardError
      { presence: :unknown, path: snapshot_path }
    end
  end
end
