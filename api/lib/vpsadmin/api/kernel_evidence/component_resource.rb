module VpsAdmin::API::KernelEvidence
  module ComponentResource
    module_function

    def define_params(resource, &extra)
      resource.params(:all) do
        integer :id
        resource VpsAdmin::API::Resources::Node, value_label: :domain_name
        string :source, choices: %w[current event], db_name: :snapshot_type
        resource VpsAdmin::API::Resources::NodeKernelEvidence, value_label: :id
        string :source_revision, db_name: :snapshot_revision
        datetime :observed_at
        instance_exec(&extra)
      end
    end
  end

  module ComponentIndex
    def self.included(action)
      action.input do
        resource VpsAdmin::API::Resources::Node, value_label: :domain_name
        bool :node_active
        string :source, choices: %w[current event]
        resource VpsAdmin::API::Resources::NodeKernelEvidence, value_label: :id
        datetime :from
        datetime :to
        patch :limit, default: 1000, fill: true
      end
      action.authorize { |user| allow if user.role == :admin }
    end

    def count = query.count

    def exec
      scope = query
      if input[:from_id]
        scope = scope.where(scope.klass.arel_table[:id].gt(input[:from_id]))
      end
      scope.limit(input[:limit])
    end
  end
end
