module VpsAdmin::API::Resources
  class NodeKernelConfigurationOption < HaveAPI::Resource
    desc 'Parsed options from exact Node kernel configurations'
    model ::NodeKernelConfigurationOption

    params(:all) do
      integer :id
      string :configuration_digest
      string :name
      string :value
    end

    class Index < HaveAPI::Actions::Default::Index
      input do
        resource VpsAdmin::API::Resources::Node, value_label: :domain_name
        bool :node_active
        string :configuration_digest, format: {
          rx: /\A[0-9a-f]{64}\z/,
          message: "'%{value}' is not a kernel configuration digest"
        }
        string :name, format: {
          rx: /\ACONFIG_[A-Z0-9_]+\z/,
          message: "'%{value}' is not a kernel configuration option"
        }
        patch :limit, default: 1000, fill: true
      end
      output(:object_list) { use :all }
      authorize { |user| allow if user.role == :admin }

      def query
        digests = VpsAdmin::API::KernelEvidence::ResourceScope.configuration_digests(input)
        scope = ::NodeKernelConfigurationOption
                .joins(:node_kernel_configuration)
                .select(
                  'node_kernel_configuration_options.*',
                  'node_kernel_configurations.digest AS configuration_digest'
                )
                .where(node_kernel_configurations: { digest: digests })
                .order(:id)
        if input[:configuration_digest]
          scope = scope.where(
            node_kernel_configurations: { digest: input[:configuration_digest] }
          )
        end
        scope = scope.where(name: input[:name]) if input[:name]
        scope
      end

      def count = query.count
      def exec = with_pagination(query)
    end
  end
end
