module VpsAdmin::API::Resources
  class DefaultObjectClusterResource < HaveAPI::Resource
    model ::DefaultObjectClusterResource
    desc 'Manage default cluster resources values for objects'

    params(:common) do
      resource Environment
      resource ClusterResource
      string :class_name
      integer :value
    end

    params(:all) do
      integer :id, label: 'ID'
      use :common
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List default cluster resource values for objects'

      input do
        use :common, include: %i[environment cluster_resource class_name]
      end

      output(:object_list) do
        use :all
      end

      authorize do
        allow
      end

      def query
        q = self.class.model

        %i[environment cluster_resource class_name].each do |v|
          q = q.where(v => input[v]) if input[v]
        end

        q
      end

      def count
        query.count
      end

      def exec
        with_includes(query)
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      desc 'Show default cluster resource values for object'

      output do
        use :all
      end

      authorize do
        allow
      end

      def prepare
        @defaut_resource_value = self.class.model.find(params[:default_object_cluster_resource_id])
      end

      def exec
        @defaut_resource_value
      end
    end

    class Create < HaveAPI::Actions::Default::Create
      desc 'Create a default cluster resource value for object'

      input do
        use :common

        %i[environment cluster_resource class_name value].each do |v|
          patch v, required: true
        end
      end

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        ::DefaultObjectClusterResource.create!(input)
      rescue ActiveRecord::RecordInvalid => e
        error('create failed', e.record.errors.to_hash)
      end
    end

    class Update < HaveAPI::Actions::Default::Update
      desc 'Update default cluster resource value for object'

      input do
        use :common, include: %i[value]
        patch :value, required: true
      end

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        ::DefaultObjectClusterResource
          .find(params[:default_object_cluster_resource_id])
          .update!(input)
      end
    end

    class Delete < HaveAPI::Actions::Default::Delete
      desc 'Delete default cluster resource value for object'

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        ::DefaultObjectClusterResource
          .find(params[:default_object_cluster_resource_id])
          .destroy!
        ok
      end
    end
  end
end
