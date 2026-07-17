module VpsAdmin::API::Resources
  class NodeKernelParameter < HaveAPI::Resource
    model ::NodeKernelParameter
    desc 'Ordered Node kernel parameters actually used at boot'
    VpsAdmin::API::KernelEvidence::ComponentResource.define_params(self) do
      integer :position
      string :name
      string :value, nullable: true
    end

    class Index < HaveAPI::Actions::Default::Index
      include VpsAdmin::API::KernelEvidence::ComponentIndex

      input do
        string :name
        string :value
      end
      output(:object_list) { use :all }

      def query
        scope = VpsAdmin::API::KernelEvidence::ResourceScope.component(
          ::NodeKernelParameter.all,
          input
        )
        scope = scope.where(name: input[:name]) if input[:name]
        scope = scope.where(value: input[:value]) if input[:value]
        scope.order(:node_kernel_evidence_id, :position)
      end
    end
  end
end
