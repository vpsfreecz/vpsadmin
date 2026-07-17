module VpsAdmin::API::Resources
  class NodeSoftwareChange < HaveAPI::Resource
    model ::NodeSoftwareChange
    desc 'Component changes within grouped Node software deployments'

    params(:all) do
      integer :id
      resource VpsAdmin::API::Resources::Node, value_label: :domain_name
      resource VpsAdmin::API::Resources::NodeKernelEvent, value_label: :id
      resource VpsAdmin::API::Resources::NodeKernelEvidence, value_label: :id
      string :source_revision
      datetime :observed_after, nullable: true
      datetime :observed_before
      string :generation, choices: ::NodeSoftwareChange.generations.keys
      string :component, choices: ::NodeSoftwareChange.components.keys
      string :before_version, nullable: true
      string :before_version_source, choices: ::NodeSoftwareChange::VERSION_SOURCES, nullable: true
      string :before_revision, nullable: true
      string :before_revision_source, choices: ::NodeSoftwareChange::REVISION_SOURCES, nullable: true
      bool :before_revision_dirty
      string :after_version, nullable: true
      string :after_version_source, choices: ::NodeSoftwareChange::VERSION_SOURCES, nullable: true
      string :after_revision, nullable: true
      string :after_revision_source, choices: ::NodeSoftwareChange::REVISION_SOURCES, nullable: true
      bool :after_revision_dirty
    end

    class Index < HaveAPI::Actions::Default::Index
      input do
        resource VpsAdmin::API::Resources::Node, value_label: :domain_name
        bool :node_active
        resource VpsAdmin::API::Resources::NodeKernelEvent, value_label: :id
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
        scope = ::NodeSoftwareChange.joins(node_kernel_event: :node)
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
        scope = scope.where(generation: input[:generation]) if input[:generation]
        scope = scope.where(component: input[:component]) if input[:component]
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
