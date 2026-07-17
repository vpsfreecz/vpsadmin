module VpsAdmin::API::Resources
  class NodeKernelEvidence < HaveAPI::Resource
    model ::NodeKernelEvidence
    desc 'Current security-relevant kernel evidence reported by Nodes'

    params(:all) do
      integer :id
      resource VpsAdmin::API::Resources::Node, value_label: :domain_name
      integer :report_schema_version, nullable: true
      datetime :observed_at, nullable: true
      datetime :received_at, nullable: true
      string :evidence_revision
      string :snapshot_revision, nullable: true
      string :boot_id, nullable: true
      datetime :booted_at, nullable: true
      string :booted_release, nullable: true
      string :reported_release, nullable: true
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
        remove :from_id
        integer :offset, default: 0, fill: true, number: { min: 0 }
        patch :limit, default: 1000, fill: true
      end
      output(:object_list) { use :all }
      authorize { |user| allow if user.role == :admin }

      def query
        scope = ::NodeKernelEvidence.current
                                    .joins(:node)
                                    .includes(:node)
                                    .where(
                                      nodes: {
                                        role: VpsAdmin::API::KernelEvidence::ResourceScope::HOST_ROLES
                                      }
                                    )
        scope = scope.where(node_id: input[:node].id) if input[:node]
        scope = scope.where(nodes: { active: input[:node_active] }) if input.has_key?(:node_active)
        scope.order(:id)
      end

      def count = query.count

      def exec
        query.offset(input[:offset]).limit(input[:limit]).map do |evidence|
          VpsAdmin::API::KernelEvidence::ResourceProjection::Evidence.new(
            evidence,
            evidence_revision: VpsAdmin::API::KernelEvidence::Revision.collection(
              evidence.node,
              evidence
            )
          )
        end
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      output { use :all }
      authorize { |user| allow if user.role == :admin }

      def prepare
        @evidence = ::NodeKernelEvidence.joins(:node)
                                        .includes(:node)
                                        .where(
                                          nodes: {
                                            role: VpsAdmin::API::KernelEvidence::ResourceScope::HOST_ROLES
                                          }
                                        )
                                        .find(path_params['node_kernel_evidence_id'])
      end

      def exec
        VpsAdmin::API::KernelEvidence::ResourceProjection::Evidence.new(
          @evidence,
          evidence_revision: VpsAdmin::API::KernelEvidence::Revision.collection(
            @evidence.node,
            @evidence
          )
        )
      end
    end
  end
end
