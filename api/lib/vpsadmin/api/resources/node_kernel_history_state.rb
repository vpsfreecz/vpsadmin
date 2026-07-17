module VpsAdmin::API::Resources
  class NodeKernelHistoryState < HaveAPI::Resource
    model ::NodeKernelHistoryState
    desc 'Coverage of reconstructed Node kernel history'

    params(:all) do
      integer :id
      resource VpsAdmin::API::Resources::Node, value_label: :domain_name
      integer :from_status_id, nullable: true
      integer :through_status_id, nullable: true
      datetime :started_at, nullable: true
      datetime :observed_through, nullable: true
      datetime :completed_at
    end

    class Index < HaveAPI::Actions::Default::Index
      input do
        resource VpsAdmin::API::Resources::Node, value_label: :domain_name
        bool :node_active
        datetime :from
        datetime :to
        patch :limit, default: 1000, fill: true
      end
      output(:object_list) { use :all }
      authorize { |user| allow if user.role == :admin }

      def query
        scope = ::NodeKernelHistoryState.joins(:node)
                                        .includes(:node)
                                        .where(
                                          nodes: {
                                            role: VpsAdmin::API::KernelEvidence::ResourceScope::HOST_ROLES
                                          }
                                        )
        scope = scope.where(node_id: input[:node].id) if input[:node]
        scope = scope.where(nodes: { active: input[:node_active] }) if input.has_key?(:node_active)
        scope = scope.where(observed_through: input[:from]..) if input[:from]
        scope = scope.where(started_at: ..input[:to]) if input[:to]
        scope.order(:id)
      end

      def count = query.count

      def exec
        scope = query
        scope = scope.where(id: (input[:from_id] + 1)..) if input[:from_id]
        scope.limit(input[:limit])
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      output { use :all }
      authorize { |user| allow if user.role == :admin }

      def prepare
        @state = ::NodeKernelHistoryState.joins(:node)
                                         .includes(:node)
                                         .where(
                                           nodes: {
                                             role: VpsAdmin::API::KernelEvidence::ResourceScope::HOST_ROLES
                                           }
                                         )
                                         .find(path_params['node_kernel_history_state_id'])
      end

      def exec = @state
    end
  end
end
