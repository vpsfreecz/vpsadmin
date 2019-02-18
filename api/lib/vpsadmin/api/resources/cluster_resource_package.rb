module VpsAdmin::API::Resources
  class ClusterResourcePackage < HaveAPI::Resource
    desc 'Manage cluster resource packages'
    model ::ClusterResourcePackage

    params(:common) do
      string :label, label: 'Label'
      resource VpsAdmin::API::Resources::Environment
      resource VpsAdmin::API::Resources::User, value_label: :login
      datetime :created_at
      datetime :updated_at
    end

    params(:all) do
      id :id
      use :common
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List cluster resource packages'

      input do
        use :common, include: %i(environment user)
      end

      output(:object_list) do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def query
        q = ::ClusterResourcePackage.all

        %i(environment user).each do |v|
          q = q.where(v => input[v]) if input.has_key?(v)
        end

        q
      end

      def count
        query.count
      end

      def exec
        with_includes(query).offset(input[:offset]).limit(input[:limit])
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      desc 'Show cluster resource package'

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def prepare
        @p = ::ClusterResourcePackage.find(params[:cluster_resource_package_id])
      end

      def exec
        @p
      end
    end

    class Create < HaveAPI::Actions::Default::Create
      desc 'Create a cluster resource package'

      input do
        use :common, include: %i(label)
        patch :label, required: true
      end

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        ::ClusterResourcePackage.create!(input)

      rescue ActiveRecord::RecordInvalid => e
        error('create failed', e.record.errors.to_hash)
      end
    end

    class Update < HaveAPI::Actions::Default::Update
      desc 'Update a cluster resource package'

      input do
        use :common, include: %i(label)
        patch :label, required: true
      end

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        ::ClusterResourcePackage.find(params[:cluster_resource_package_id]).update!(input)

      rescue ActiveRecord::RecordInvalid => e
        error('update failed', e.record.errors.to_hash)
      end
    end

    class Delete < HaveAPI::Actions::Default::Delete
      desc 'Delete a cluster resource package'

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        pkg = ::ClusterResourcePackage.find(params[:cluster_resource_package_id])

        if pkg.can_destroy?
          pkg.destroy!
        else
          error('user resource packages cannot be destroyed independently')
        end

        ok
      end
    end

    class Item < HaveAPI::Resource
      desc "Manage cluster resource package contents"
      model ::ClusterResourcePackageItem
      route ':cluster_resource_package_id/items'

      params(:common) do
        resource VpsAdmin::API::Resources::ClusterResource
        integer :value
      end

      params(:all) do
        id :id
        use :common
      end

      class Index < HaveAPI::Actions::Default::Index
        desc 'List cluster resource package contents'

        output(:object_list) do
          use :all
        end

        authorize do |u|
          allow if u.role == :admin
        end

        def query
          ::ClusterResourcePackageItem.where(
            cluster_resource_package_id: params[:cluster_resource_package_id],
          )
        end

        def count
          query.count
        end

        def exec
          with_includes(query).offset(input[:offset]).limit(input[:limit])
        end
      end

      class Show < HaveAPI::Actions::Default::Show
        desc 'Show cluster resource package item'

        output do
          use :all
        end

        authorize do |u|
          allow if u.role == :admin
        end

        def prepare
          @it = ::ClusterResourcePackageItem.where(
            cluster_resource_package_id: params[:cluster_resource_package_id],
            id: params[:item_id],
          ).take!
        end

        def exec
          @it
        end
      end

      class Create < HaveAPI::Actions::Default::Create
        desc 'Add item to a cluster resource package'

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
          ::ClusterResourcePackage
            .find(params[:cluster_resource_package_id])
            .add_item(input[:cluster_resource], input[:value])

        rescue ActiveRecord::RecordInvalid => e
          error('create failed', e.record.errors.to_hash)

        rescue ActiveRecord::RecordNotUnique
          error('this resource already exists')
        end
      end

      class Update < HaveAPI::Actions::Default::Update
        desc 'Update item in a cluster resource package'

        input do
          use :common, include: %i(value)
        end

        output do
          use :all
        end

        authorize do |u|
          allow if u.role == :admin
        end

        def exec
          it = ::ClusterResourcePackageItem.where(
            cluster_resource_package_id: params[:cluster_resource_package_id],
            id: params[:item_id],
          ).take!
          it.cluster_resource_package.update_item(it, input[:value])

        rescue ActiveRecord::RecordInvalid => e
          error('update failed', e.record.errors.to_hash)
        end
      end

      class Delete < HaveAPI::Actions::Default::Delete
        desc 'Delete an item from a cluster resource package'

        authorize do |u|
          allow if u.role == :admin
        end

        def exec
          it = ::ClusterResourcePackageItem.where(
            cluster_resource_package_id: params[:cluster_resource_package_id],
            id: params[:item_id],
          ).take!
          it.cluster_resource_package.remove_item(it)
          ok
        end
      end
    end
  end
end
