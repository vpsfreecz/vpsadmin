module VpsAdmin::API::Resources
  class NodeKernelLivepatchPatch < HaveAPI::Resource
    model ::NodeKernelLivepatchPatch
    desc 'Individual changes carried by Node kernel livepatch modules'
    VpsAdmin::API::KernelEvidence::ComponentResource.define_params(self) do
      resource VpsAdmin::API::Resources::NodeKernelLivepatch, value_label: :livepatch_id
      string :name
      string :version, nullable: true
    end

    class Index < HaveAPI::Actions::Default::Index
      include VpsAdmin::API::KernelEvidence::ComponentIndex

      input do
        resource VpsAdmin::API::Resources::NodeKernelLivepatch, value_label: :livepatch_id
        string :name
      end
      output(:object_list) { use :all }

      def query
        scope = ::NodeKernelLivepatchPatch.joins(
          node_kernel_livepatch: { node_kernel_evidence: :node }
        )
        scope = VpsAdmin::API::KernelEvidence::ResourceScope.nested_component(scope, input)
        if input[:node_kernel_livepatch]
          scope = scope.where(node_kernel_livepatches: { id: input[:node_kernel_livepatch].id })
        end
        scope = scope.where(name: input[:name]) if input[:name]
        scope.order(:id)
      end
    end
  end
end
