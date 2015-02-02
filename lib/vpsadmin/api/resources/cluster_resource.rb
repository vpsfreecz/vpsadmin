module VpsAdmin::API::Resources
  class ClusterResource < HaveAPI::Resource
    desc 'Manage environment resources'
    version 1
    model ::ClusterResource

    params(:common) do
      string :name, label: 'Resource name for internal purposes'
      string :label, label: 'Label'
      integer :min, label: 'Minimum value',
              desc: 'When an object is allocating a resource, it must use more than minimum'
      integer :max, label: 'Maximum value',
              desc: 'When an object is allocating a resource, it must not use more than maximum'
      integer :stepsize, label: 'Step size',
          desc: 'Steps in which the objects allocated resource value may be iterated'
    end

    params(:all) do
      id :id
      use :common
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List environment resources'

      output(:object_list) do
        use :all
      end

      authorize do |u|
        allow
      end

      def query
        ::ClusterResource.all
      end

      def count
        query.count
      end

      def exec
        query.offset(input[:offset]).limit(input[:limit])
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      desc 'Show environment resource'

      output do
        use :all
      end

      authorize do |u|
        allow
      end

      def prepare
        @r = ::ClusterResource.find(params[:cluster_resource_id])
      end

      def exec
        @r
      end
    end

    class Create < HaveAPI::Actions::Default::Create
      desc 'Create an environment resource'

      input do
        use :common
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        ::ClusterResource.create!(input)

      rescue ActiveRecord::RecordInvalid => e
        error('create failed', e.record.errors.to_hash)
      end
    end

    class Update < HaveAPI::Actions::Default::Update
      desc 'Update an environment resource'

      input do
        use :common
      end

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        ::ClusterResource.find(params[:cluster_resource_id]).update!(input)

      rescue ActiveRecord::RecordInvalid => e
        error('update failed', e.record.errors.to_hash)
      end
    end
  end
end
