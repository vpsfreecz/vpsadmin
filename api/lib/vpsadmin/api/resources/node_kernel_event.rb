module VpsAdmin::API::Resources
  class NodeKernelEvent < HaveAPI::Resource
    model ::NodeKernelEvent
    desc 'Exact internal Node kernel evidence history'

    params(:all) do
      integer :id
      resource VpsAdmin::API::Resources::Node, value_label: :domain_name
      resource VpsAdmin::API::Resources::NodeKernelEvidence,
               value_label: :id,
               db_name: :kernel_evidence,
               nullable: true
      string :event_type, choices: ::NodeKernelEvent.event_types.keys
      string :boot_id, nullable: true
      datetime :booted_at, nullable: true
      string :booted_release, nullable: true
      string :reported_release
      datetime :effective_at, nullable: true
      datetime :observed_after,
               desc: 'Last observation before the change; null for the first known event',
               nullable: true
      datetime :observed_before,
               desc: 'First observation containing the change'
      string :source, choices: ::NodeKernelEvent.sources.keys
      integer :source_status_id, nullable: true
      string :confidence, choices: ::NodeKernelEvent.confidences.keys
      bool :current
      integer :report_schema_version, nullable: true
      string :evidence_revision
      string :snapshot_revision, nullable: true
      string :kernel_source_revision, nullable: true
      string :kernel_config_digest, nullable: true
      bool :kernel_config_available
      string :kernel_command_line, nullable: true
      string :booted_system, nullable: true
      string :current_system, nullable: true
    end

    class Index < HaveAPI::Actions::Default::Index
      input do
        resource VpsAdmin::API::Resources::Node, value_label: :domain_name
        bool :node_active
        datetime :from
        datetime :to
        string :event_type, choices: ::NodeKernelEvent.event_types.keys
        string :event_source, choices: ::NodeKernelEvent.sources.keys
        string :confidence, choices: ::NodeKernelEvent.confidences.keys
        bool :current
        patch :limit, default: 1000, fill: true
      end
      output(:object_list) { use :all }
      authorize { |user| allow if user.role == :admin }

      def rows
        @rows ||= VpsAdmin::API::KernelEvidence::ResourceScope.events(
          VpsAdmin::API::KernelEvidence::ResourceScope.nodes(input),
          input
        )
      end

      def count = rows.count

      def exec
        scope = rows
        scope = scope.where(id: (input[:from_id] + 1)..) if input[:from_id]
        scope.limit(input[:limit]).map do |event|
          VpsAdmin::API::KernelEvidence::ResourceProjection::Event.new(
            event,
            evidence_revision: VpsAdmin::API::KernelEvidence::Revision.event(event)
          )
        end
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      output { use :all }
      authorize { |user| allow if user.role == :admin }

      def prepare
        @event = ::NodeKernelEvent.joins(:node)
                                  .includes(:node, :kernel_evidence)
                                  .where(
                                    nodes: {
                                      role: VpsAdmin::API::KernelEvidence::ResourceScope::HOST_ROLES
                                    }
                                  )
                                  .find(path_params['node_kernel_event_id'])
      end

      def exec
        VpsAdmin::API::KernelEvidence::ResourceProjection::Event.new(
          @event,
          evidence_revision: VpsAdmin::API::KernelEvidence::Revision.event(@event)
        )
      end
    end
  end
end
