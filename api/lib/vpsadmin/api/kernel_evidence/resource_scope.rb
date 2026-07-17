module VpsAdmin::API::KernelEvidence
  module ResourceScope
    HOST_ROLES = %i[node storage].freeze

    module_function

    def nodes(input)
      scope = ::Node.where(role: HOST_ROLES)
                    .includes(
                      node_current_status: :kernel_evidence,
                      node_kernel_history_state: :kernel_history_gaps
                    )
                    .order(:id)
      scope = scope.where(id: input[:node].id) if input[:node]
      active = input[:node_active] if input.has_key?(:node_active)
      scope = scope.where(active:) unless active.nil?
      scope
    end

    def events(nodes, input)
      filtered = ::NodeKernelEvent.where(node_id: nodes.select(:id))
      filtered = filtered.where(observed_before: ..input[:to]) if input[:to]
      filtered = filtered.where(event_type: input[:event_type]) if input[:event_type]
      filtered = filtered.where(source: input[:event_source]) if input[:event_source]
      filtered = filtered.where(confidence: input[:confidence]) if input[:confidence]
      filtered = filtered.where(current: input[:current]) if input.has_key?(:current)

      window = input[:from] ? filtered.where(observed_before: input[:from]..) : filtered
      selected = ::NodeKernelEvent.where(id: window.select(:id))
      selected = selected.or(baseline_events(filtered, input[:from])) if input[:from]
      selected.includes(:node, :kernel_evidence).order(:id)
    end

    def component(scope, input)
      scope = scope.joins(node_kernel_evidence: :node)
                   .includes(node_kernel_evidence: :node)
                   .where(nodes: { role: HOST_ROLES })
      scope = scope.where(node_kernel_evidences: { node_id: input[:node].id }) if input[:node]
      scope = scope.where(nodes: { active: input[:node_active] }) if input.has_key?(:node_active)
      if input[:source]
        scope = scope.where(
          node_kernel_evidences: {
            snapshot_type: ::NodeKernelEvidence.snapshot_types.fetch(input[:source])
          }
        )
      end
      if input[:node_kernel_evidence]
        scope = scope.where(node_kernel_evidences: { id: input[:node_kernel_evidence].id })
      end
      scope = scope.where(node_kernel_evidences: { observed_at: input[:from].. }) if input[:from]
      scope = scope.where(node_kernel_evidences: { observed_at: ..input[:to] }) if input[:to]
      scope
    end

    def nested_component(scope, input)
      evidence = ::NodeKernelEvidence.arel_table
      scope = scope.where(nodes: { role: HOST_ROLES })
      scope = scope.where(evidence[:node_id].eq(input[:node].id)) if input[:node]
      scope = scope.where(nodes: { active: input[:node_active] }) if input.has_key?(:node_active)
      if input[:source]
        scope = scope.where(
          evidence[:snapshot_type].eq(::NodeKernelEvidence.snapshot_types.fetch(input[:source]))
        )
      end
      if input[:node_kernel_evidence]
        scope = scope.where(evidence[:id].eq(input[:node_kernel_evidence].id))
      end
      scope = scope.where(evidence[:observed_at].gteq(input[:from])) if input[:from]
      scope = scope.where(evidence[:observed_at].lteq(input[:to])) if input[:to]
      scope
    end

    def configuration_digests(input)
      scope = ::NodeKernelEvidence.joins(:node).where(nodes: { role: HOST_ROLES })
      scope = scope.where(node_id: input[:node].id) if input[:node]
      scope = scope.where(nodes: { active: input[:node_active] }) if input.has_key?(:node_active)
      scope.where.not(kernel_config_digest: nil).distinct.pluck(:kernel_config_digest)
    end

    def baseline_events(filtered, from)
      ranked_sql = filtered
                   .where(observed_before: ..from)
                   .reorder(nil)
                   .select(
                     'node_kernel_events.id',
                     <<~SQL.squish
                       ROW_NUMBER() OVER (
                         PARTITION BY node_kernel_events.node_id
                         ORDER BY node_kernel_events.observed_before DESC,
                                  node_kernel_events.id DESC
                       ) AS baseline_position
                     SQL
                   )
                   .to_sql
      baseline_ids = ::NodeKernelEvent.unscoped
                                      .from("(#{ranked_sql}) node_kernel_event_baselines")
                                      .where('node_kernel_event_baselines.baseline_position = 1')
                                      .select('node_kernel_event_baselines.id')
      ::NodeKernelEvent.where(id: baseline_ids)
    end

    private_class_method :baseline_events
  end
end
