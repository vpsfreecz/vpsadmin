module VpsAdmin::API::Resources
  class NodeKernelHistoryGap < HaveAPI::Resource
    model ::NodeKernelHistoryGap
    desc 'Missing intervals in reconstructed Node kernel history'

    params(:all) do
      integer :id
      resource VpsAdmin::API::Resources::NodeKernelHistoryState, value_label: :id
      resource VpsAdmin::API::Resources::Node, value_label: :domain_name
      datetime :from
      datetime :to
      string :reason
    end

    class Index < HaveAPI::Actions::Default::Index
      input do
        resource VpsAdmin::API::Resources::Node, value_label: :domain_name
        bool :node_active
        resource VpsAdmin::API::Resources::NodeKernelHistoryState, value_label: :id
        datetime :from
        datetime :to
        patch :limit, default: 1000, fill: true
      end
      output(:object_list) { use :all }
      authorize { |user| allow if user.role == :admin }

      def query
        scope = ::NodeKernelHistoryGap.joins(node_kernel_history_state: :node)
                                      .includes(node_kernel_history_state: :node)
                                      .where(
                                        nodes: {
                                          role: VpsAdmin::API::KernelEvidence::ResourceScope::HOST_ROLES
                                        }
                                      )
        if input[:node_kernel_history_state]
          scope = scope.where(node_kernel_history_state_id: input[:node_kernel_history_state].id)
        end
        if input[:node]
          scope = scope.where(node_kernel_history_states: { node_id: input[:node].id })
        end
        scope = scope.where(nodes: { active: input[:node_active] }) if input.has_key?(:node_active)
        scope = scope.where(to: input[:from]..) if input[:from]
        scope = scope.where(from: ..input[:to]) if input[:to]
        scope.order(:id)
      end

      def count = query.count

      def exec
        scope = query
        scope = scope.where(id: (input[:from_id] + 1)..) if input[:from_id]
        scope.limit(input[:limit])
      end
    end
  end
end
