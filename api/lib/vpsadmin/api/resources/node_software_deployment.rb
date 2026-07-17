module VpsAdmin::API::Resources
  class NodeSoftwareDeployment < HaveAPI::Resource
    model ::NodeKernelEvent
    desc 'Grouped Node software deployment history'

    params(:all) do
      integer :id
      resource VpsAdmin::API::Resources::Node, value_label: :domain_name
      resource VpsAdmin::API::Resources::NodeKernelEvidence,
               value_label: :id,
               db_name: :kernel_evidence
      string :source_revision
      string :event_type, choices: ::NodeKernelEvent.event_types.keys
      datetime :effective_at, nullable: true
      datetime :observed_after, nullable: true
      datetime :observed_before
      string :booted_system, nullable: true
      string :current_system, nullable: true
      integer :change_count
    end

    class Index < HaveAPI::Actions::Default::Index
      input do
        resource VpsAdmin::API::Resources::Node, value_label: :domain_name
        bool :node_active
        datetime :from
        datetime :to
        string :generation, choices: ::NodeSoftwareChange.generations.keys
        string :component, choices: ::NodeSoftwareChange.components.keys
        remove :from_id
        integer :offset, default: 0, fill: true, number: { min: 0 }
        patch :limit, default: 1000, fill: true
      end
      output(:object_list) { use :all }
      authorize { |user| allow if user.role == :admin }

      def query
        scope = ::NodeKernelEvent.joins(:node, :software_changes)
                                 .includes(:node, :kernel_evidence, :software_changes)
                                 .where(
                                   nodes: {
                                     role: VpsAdmin::API::KernelEvidence::ResourceScope::HOST_ROLES
                                   }
                                 )
        scope = scope.where(node_id: input[:node].id) if input[:node]
        scope = scope.where(nodes: { active: input[:node_active] }) if input.has_key?(:node_active)
        scope = scope.where(observed_before: input[:from]..) if input[:from]
        scope = scope.where(observed_before: ..input[:to]) if input[:to]
        scope = scope.where(node_software_changes: { generation: input[:generation] }) if input[:generation]
        scope = scope.where(node_software_changes: { component: input[:component] }) if input[:component]
        scope.distinct.order(observed_before: :desc, id: :desc)
      end

      def count = query.count

      def exec
        query.offset(input[:offset]).limit(input[:limit]).map do |event|
          VpsAdmin::API::KernelEvidence::ResourceProjection::Event.new(event)
        end
      end
    end
  end
end
