module VpsAdmin::API::Resources
  class NodeKernelModule < HaveAPI::Resource
    model ::NodeKernelModule
    desc 'Loaded Node kernel modules'
    VpsAdmin::API::KernelEvidence::ComponentResource.define_params(self) { string :name }

    class Index < HaveAPI::Actions::Default::Index
      include VpsAdmin::API::KernelEvidence::ComponentIndex

      input { string :name }
      output(:object_list) { use :all }

      def query
        scope = VpsAdmin::API::KernelEvidence::ResourceScope.component(
          ::NodeKernelModule.all,
          input
        )
        input[:name] ? scope.where(name: input[:name]).order(:id) : scope.order(:id)
      end
    end
  end
end
