require 'digest'
require 'json'

module VpsAdmin::API
  # Version 1 wire shape is documented in docs/storage/remove-snapshots.md.
  class Operations::Dataset::SnapshotRemovalManifest
    def initialize(scope)
      @scope = scope
    end

    def export
      value = manifest
      encoded = JSON.generate(canonical(manifest_version: 1, manifest: value))
      { manifest_version: 1, manifest_digest: "v1:#{Digest::SHA256.hexdigest(encoded)}", manifest: value }
    end

    protected

    def manifest
      datasets = @scope.sources.map(&:dataset).sort_by(&:id).map do |dataset|
        dataset.attributes.symbolize_keys.slice(:id, :parent_id, :user_id, :name, :full_name, :current_history_id)
               .merge(parent_id: dataset.parent_id)
      end
      copies = @scope.copies.map do |copy|
        pool = copy.pool
        { id: copy.id, dataset_id: copy.dataset_id, pool_id: pool.id, pool_label: pool.label,
          pool_role: pool.role, pool_filesystem: pool.filesystem, pool_open: pool.is_open == 1,
          node_id: pool.node_id, node_name: pool.node.name }
      end
      locations = @scope.all_snapshots.flat_map do |sip|
        memberships = @scope.entries.select { |entry| entry.snapshot_in_pool_id == sip.id }
        memberships = [nil] if memberships.empty?
        memberships.map { |entry| location(sip, entry) }
      end.sort_by { |row| [row[:dataset_in_pool_id], row[:snapshot_id], row[:snapshot_in_pool_in_branch_id] || 0, row[:snapshot_in_pool_id]] }
      trees = @scope.trees.map { |tree| { id: tree.id, dataset_in_pool_id: tree.dataset_in_pool_id, name: tree.full_name, head: tree.head } }
      branches = @scope.branches.map { |branch| { id: branch.id, dataset_tree_id: branch.dataset_tree_id, name: branch.full_name, head: branch.head } }
      plans = @scope.sources.flat_map do |source|
        @scope.plans.select { |plan| plan.dataset_in_pool_id == source.id }.map do |plan|
          definition = plan.environment_dataset_plan.dataset_plan
          { id: plan.id, dataset_in_pool_id: source.id, environment_dataset_plan_id: plan.environment_dataset_plan_id,
            dataset_plan_id: definition.id, name: definition.name, action: @scope.disable_plans ? 'remove' : 'retain' }
        end
      end.sort_by { |row| row[:id] }
      { root_dataset_id: @scope.root.id, options: { recursive: @scope.recursive, disable_plans: @scope.disable_plans },
        datasets:, copies:, snapshot_locations: locations, trees:, branches:, plans:,
        counts: { datasets: datasets.size, copies: copies.size, snapshots: locations.map { |row| row[:snapshot_id] }.uniq.size,
                  snapshot_locations: locations.size, trees: trees.size, branches: branches.size,
                  plans: plans.size, plans_to_disable: plans.count { |row| row[:action] == 'remove' } } }
    end

    def location(sip, entry)
      snapshot = sip.snapshot
      { snapshot_id: snapshot.id, snapshot_name: snapshot.name, snapshot_label: snapshot.label,
        created_at: snapshot.created_at&.utc&.iso8601, history_id: snapshot.history_id,
        dataset_in_pool_id: sip.dataset_in_pool_id, snapshot_in_pool_id: sip.id,
        snapshot_in_pool_in_branch_id: entry&.id, branch_id: entry&.branch_id,
        origin_snapshot_in_pool_in_branch_id: entry&.snapshot_in_pool_in_branch_id }
    end

    def canonical(value)
      case value
      when Hash
        value.sort_by { |key, _| key.to_s }.to_h.transform_values { |item| canonical(item) }
      when Array
        value.map { |item| canonical(item) }
      else
        value
      end
    end
  end
end
