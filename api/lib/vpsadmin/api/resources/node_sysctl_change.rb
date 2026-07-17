module VpsAdmin::API::Resources
  class NodeSysctlChange < HaveAPI::Resource
    model ::NodeSysctlChange
    desc 'Per-name Node sysctl history'

    params(:all) do
      integer :id
      resource VpsAdmin::API::Resources::Node, value_label: :domain_name
      resource VpsAdmin::API::Resources::NodeKernelEvent, value_label: :id
      resource VpsAdmin::API::Resources::NodeKernelEvidence, value_label: :id
      string :source_revision
      datetime :observed_after, nullable: true
      datetime :observed_before
      string :name
      bool :before_available, nullable: true
      string :before_configured_value, nullable: true
      string :before_effective_value, nullable: true
      bool :after_available, nullable: true
      string :after_configured_value, nullable: true
      string :after_effective_value, nullable: true
    end

    class Index < HaveAPI::Actions::Default::Index
      input do
        resource VpsAdmin::API::Resources::Node, value_label: :domain_name
        bool :node_active
        resource VpsAdmin::API::Resources::NodeKernelEvent, value_label: :id
        datetime :from
        datetime :to
        string :name
        remove :from_id
        integer :offset, default: 0, fill: true, number: { min: 0 }
        patch :limit, default: 1000, fill: true
      end
      output(:object_list) { use :all }
      authorize { |user| allow if user.role == :admin }

      def query
        scope = ::NodeSysctlChange.joins(node_kernel_event: :node)
                                  .includes(node_kernel_event: %i[node kernel_evidence])
                                  .where(
                                    nodes: {
                                      role: VpsAdmin::API::KernelEvidence::ResourceScope::HOST_ROLES
                                    }
                                  )
        scope = scope.where(node_kernel_events: { node_id: input[:node].id }) if input[:node]
        scope = scope.where(nodes: { active: input[:node_active] }) if input.has_key?(:node_active)
        if input[:node_kernel_event]
          scope = scope.where(node_kernel_event_id: input[:node_kernel_event].id)
        end
        scope = scope.where(node_kernel_events: { observed_before: input[:from].. }) if input[:from]
        scope = scope.where(node_kernel_events: { observed_before: ..input[:to] }) if input[:to]
        scope = scope.where(name: input[:name]) if input[:name]
        scope.order('node_kernel_events.observed_before DESC', id: :desc)
      end

      def count = query.count

      def exec
        query.offset(input[:offset]).limit(input[:limit]).map do |change|
          VpsAdmin::API::KernelEvidence::ResourceProjection::Change.new(change)
        end
      end
    end
  end
end
