module VpsAdmin::API::Resources
  class NodeKernelLivepatch < HaveAPI::Resource
    model ::NodeKernelLivepatch
    desc 'Node kernel livepatch modules'
    VpsAdmin::API::KernelEvidence::ComponentResource.define_params(self) do
      string :livepatch_id
      string :kernel_version, nullable: true
      string :patch_version, nullable: true
      bool :loaded, nullable: true
      bool :enabled, nullable: true
      bool :transition, nullable: true
      datetime :applied_at, nullable: true
      datetime :verified_at, nullable: true
    end

    class Index < HaveAPI::Actions::Default::Index
      include VpsAdmin::API::KernelEvidence::ComponentIndex

      input { string :livepatch_id }
      output(:object_list) { use :all }

      def query
        scope = VpsAdmin::API::KernelEvidence::ResourceScope.component(
          ::NodeKernelLivepatch.all,
          input
        )
        scope = scope.where(livepatch_id: input[:livepatch_id]) if input[:livepatch_id]
        scope.order(:id)
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      output { use :all }
      authorize { |user| allow if user.role == :admin }

      def prepare
        @livepatch = VpsAdmin::API::KernelEvidence::ResourceScope.component(
          ::NodeKernelLivepatch.all,
          {}
        ).find(path_params['node_kernel_livepatch_id'])
      end

      def exec = @livepatch
    end
  end
end
