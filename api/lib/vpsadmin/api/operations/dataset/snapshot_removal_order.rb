module VpsAdmin::API
  # A deletion order for one bounded inventory, not a general graph service.
  class Operations::Dataset::SnapshotRemovalOrder
    def initialize(branches, entries, snapshots)
      @branches = branches.index_by(&:id)
      @entries = entries.index_by(&:id)
      @snapshots = snapshots.index_by(&:id)
    end

    def order
      dependents = Hash.new { |hash, key| hash[key] = [] }
      references = Hash.new(0)
      @entries.each_value do |entry|
        next unless entry.snapshot_in_pool_in_branch_id

        origin = @entries[entry.snapshot_in_pool_in_branch_id]
        if !origin || origin.branch_id == entry.branch_id ||
           origin.snapshot_in_pool.dataset_in_pool_id != entry.snapshot_in_pool.dataset_in_pool_id
          reject!("membership #{entry.id} has an invalid origin")
        end
        references[origin.snapshot_in_pool_id] += 1
        dependents[origin.branch_id] << entry.branch_id
      end
      @snapshots.each_value do |sip|
        reject!("snapshot copy #{sip.id} has external references") unless sip.reference_count == references[sip.id]
      end
      # Incoming links from outside the inventory cannot be reconciled safely,
      # even if a corrupt counter happens to conceal them.
      if ::SnapshotInPoolInBranch.where(snapshot_in_pool_in_branch_id: @entries.keys).where.not(id: @entries.keys).exists?
        reject!('backup history has external dependents')
      end

      ordered = []
      remaining = @branches.keys.sort
      until remaining.empty?
        leaves = remaining.reject { |id| dependents[id].intersect?(remaining) }
                          .sort_by { |id| [@entries.values.any? { |entry| entry.branch_id == id } ? 1 : 0, id] }
        reject!('backup history has cyclic origins') if leaves.empty?
        ordered.concat(leaves.map { |id| @branches.fetch(id) })
        remaining -= leaves
      end
      ordered
    end

    protected

    def reject!(message)
      raise Operations::Dataset::DisableBackups::Rejected, message
    end
  end
end
