module VpsAdmin::API::Resources
  class NodeEbpfProgram < HaveAPI::Resource
    model ::NodeEbpfProgram
    desc 'Node eBPF mitigation programs'
    VpsAdmin::API::KernelEvidence::ComponentResource.define_params(self) do
      string :name
      string :description, nullable: true
      string :since_kernel, nullable: true
      string :until_kernel, nullable: true
      string :revision, nullable: true
      string :digest, nullable: true
      bool :active
      datetime :attached_at, nullable: true
      datetime :verified_at, nullable: true
    end

    class Index < HaveAPI::Actions::Default::Index
      include VpsAdmin::API::KernelEvidence::ComponentIndex

      input do
        string :name
        bool :active
      end
      output(:object_list) { use :all }

      def query
        scope = VpsAdmin::API::KernelEvidence::ResourceScope.component(
          ::NodeEbpfProgram.all,
          input
        )
        scope = scope.where(name: input[:name]) if input[:name]
        scope = scope.where(active: input[:active]) if input.has_key?(:active)
        scope.order(:id)
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      output { use :all }
      authorize { |user| allow if user.role == :admin }

      def prepare
        @program = VpsAdmin::API::KernelEvidence::ResourceScope.component(
          ::NodeEbpfProgram.all,
          {}
        ).find(path_params['node_ebpf_program_id'])
      end

      def exec = @program
    end
  end
end
