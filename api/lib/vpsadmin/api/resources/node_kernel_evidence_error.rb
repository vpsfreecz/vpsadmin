module VpsAdmin::API::Resources
  class NodeKernelEvidenceError < HaveAPI::Resource
    model ::NodeKernelEvidenceError
    desc 'Errors reported while collecting Node kernel evidence'
    VpsAdmin::API::KernelEvidence::ComponentResource.define_params(self) do
      string :component
      string :reason
    end

    class Index < HaveAPI::Actions::Default::Index
      include VpsAdmin::API::KernelEvidence::ComponentIndex

      input { string :component }
      output(:object_list) { use :all }

      def query
        scope = VpsAdmin::API::KernelEvidence::ResourceScope.component(
          ::NodeKernelEvidenceError.all,
          input
        )
        scope = scope.where(component: input[:component]) if input[:component]
        scope.order(:id)
      end
    end
  end
end
