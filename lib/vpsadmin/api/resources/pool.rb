module VpsAdmin::API::Resources
  class Pool < HaveAPI::Resource
    model ::Pool
    desc 'Manage storage pools'

    params(:common) do
      resource Node, value_label: :domain_name
      string :label
      string :filesystem
      string :role, choices: ::Pool.roles.keys
      bool :refquota_check, label: 'Refquota check'
    end
    
    params(:all_properties) do
      VpsAdmin::API::DatasetProperties.to_params(self, :all)
    end

    params(:editable_properties) do
      VpsAdmin::API::DatasetProperties.to_params(self, :rw)
    end

    params(:all) do
      id :id
      use :common
      use :all_properties
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List storage pools'

      input do
        use :common
        use :editable_properties
      end

      output(:object_list) do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def query
        q = ::Pool.all
        q = q.where(node: input[:node]) if input[:node]
        q = q.where(label: input[:label]) if input[:label]
        q = q.where(filesystem: input[:filesystem]) if input[:filesystem]
        q = q.where(role: ::Pool.roles[input[:role]]) if input[:role]
        q = q.where(refquota_check: input[:refquota_check]) if input[:refquota_check]
        q
      end

      def count
        query.count
      end

      def exec
        query.limit(input[:limit]).offset(input[:offset])
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      desc 'Show storage pool'

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end
      
      def prepare
        @pool = ::Pool.find(params[:pool_id])
      end

      def exec
        @pool
      end
    end

    class Create < HaveAPI::Actions::Default::Create
      desc 'Create a new storage pool'

      input do
        use :common
        use :editable_properties
      end

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end
      
      def exec
        properties = VpsAdmin::API::DatasetProperties.validate_params(input)
        
        ::Pool.create!(input, properties)

      rescue VpsAdmin::API::Exceptions::PropertyInvalid => e
        error("property invalid: #{e.message}")

      rescue ActiveRecord::RecordInvalid => e
        error('create failed', e.record.errors.to_hash)
      end
    end

    include VpsAdmin::API::Maintainable::Action
  end
end
