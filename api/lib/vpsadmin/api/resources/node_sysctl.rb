module VpsAdmin::API::Resources
  class NodeSysctl < HaveAPI::Resource
    model ::NodeSysctl
    desc 'Configured and effective Node kernel sysctls'
    VpsAdmin::API::KernelEvidence::ComponentResource.define_params(self) do
      string :name
      bool :available
      string :configured_value, nullable: true
      string :effective_value, nullable: true
    end

    class Index < HaveAPI::Actions::Default::Index
      include VpsAdmin::API::KernelEvidence::ComponentIndex

      input { string :name }
      output(:object_list) { use :all }

      def query
        scope = VpsAdmin::API::KernelEvidence::ResourceScope.component(::NodeSysctl.all, input)
        input[:name] ? scope.where(name: input[:name]).order(:id) : scope.order(:id)
      end
    end
  end
end
