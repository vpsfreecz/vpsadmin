module VpsAdmin::API::Resources
  class NodeEbpfProgramLink < HaveAPI::Resource
    model ::NodeEbpfProgramLink
    desc 'Pinned link fields used by Node eBPF mitigations'
    VpsAdmin::API::KernelEvidence::ComponentResource.define_params(self) do
      resource VpsAdmin::API::Resources::NodeEbpfProgram, value_label: :name
      string :name
      bool :attached
    end

    class Index < HaveAPI::Actions::Default::Index
      include VpsAdmin::API::KernelEvidence::ComponentIndex

      input do
        resource VpsAdmin::API::Resources::NodeEbpfProgram, value_label: :name
        string :name
      end
      output(:object_list) { use :all }

      def query
        scope = ::NodeEbpfProgramLink.joins(
          node_ebpf_program: { node_kernel_evidence: :node }
        )
        scope = VpsAdmin::API::KernelEvidence::ResourceScope.nested_component(scope, input)
        if input[:node_ebpf_program]
          scope = scope.where(node_ebpf_programs: { id: input[:node_ebpf_program].id })
        end
        scope = scope.where(name: input[:name]) if input[:name]
        scope.order(:id)
      end
    end
  end
end
