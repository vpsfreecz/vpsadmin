class VpsAdmin::API::Resources::UserClusterResourcePackage < HaveAPI::Resource
  desc "Manage user cluster resource packages"
  model ::UserClusterResourcePackage

  params(:common) do
    resource VpsAdmin::API::Resources::Environment
    resource VpsAdmin::API::Resources::User, value_label: :login
    resource VpsAdmin::API::Resources::ClusterResourcePackage
    resource VpsAdmin::API::Resources::User, name: :added_by, value_label: :login
    string :label
    bool :is_personal
    text :comment
    datetime :created_at
    datetime :updated_at
  end

  params(:all) do
    id :id
    use :common
  end

  class Index < HaveAPI::Actions::Default::Index
    desc 'List user cluster resource packages'

    input do
      use :common, include: %i(environment user cluster_resource_package added_by)
    end

    output(:object_list) do
      use :all
    end

    authorize do |u|
      allow if u.role == :admin
      input blacklist: %i(user cluster_resource_package)
      output whitelist: %i(id environment label comment created_at updated_at)
      restrict user_id: u.id
      allow
    end

    def query
      q = ::UserClusterResourcePackage.where(with_restricted)

      %i(environment user cluster_resource_package added_by).each do |v|
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
    desc 'Show user cluster resource package'

    output do
      use :all
    end

    authorize do |u|
      allow if u.role == :admin
      output whitelist: %i(id environment label comment created_at updated_at)
      restrict user_id: u.id
      allow
    end

    def prepare
      @p = with_includes.where(with_restricted(
        id: params[:user_cluster_resource_package_id],
      )).take!
    end

    def exec
      @p
    end
  end

  class Create < HaveAPI::Actions::Default::Create
    desc 'Assign cluster resource package to user'

    input do
      params = %i(environment user cluster_resource_package comment)
      use :common, include: params
      bool :from_personal,
        label: 'From personal package',
        desc: 'Substract the added resources from the personal package',
        default: false,
        fill: true

      params.each { |p| patch(p, required: true) }
    end

    output do
      use :all
    end

    authorize do |u|
      allow if u.role == :admin
    end

    def exec
      input[:cluster_resource_package].assign_to(
        input[:environment],
        input[:user],
        comment: input[:comment],
        from_personal: input[:from_personal]
      )

    rescue VpsAdmin::API::Exceptions::UserResourceAllocationError => e
      error(e.message)
    end
  end

  class Update < HaveAPI::Actions::Default::Update
    desc 'Update user cluster resource package'

    input do
      use :common, include: %i(comment)
      patch :comment, required: true
    end

    output do
      use :all
    end

    authorize do |u|
      allow if u.role == :admin
    end

    def exec
      upkg = ::UserClusterResourcePackage.find(params[:user_cluster_resource_package_id])
      upkg.update!(input)

    rescue ActiveRecord::RecordInvalid => e
      error('update failed', e.record.errors.to_hash)
    end
  end

  class Delete < HaveAPI::Actions::Default::Delete
    desc 'Remove cluster resource package from user'

    authorize do |u|
      allow if u.role == :admin
    end

    def exec
      user_pkg = ::UserClusterResourcePackage.find(params[:user_cluster_resource_package_id])

      if user_pkg.can_destroy?
        user_pkg.destroy!
        ok
      else
        error('this package cannot be removed')
      end
    end
  end

  class Item < HaveAPI::Resource
    desc "View user cluster resource package contents"
    route ':user_cluster_resource_package_id/items'
    model ::ClusterResourcePackageItem

    params(:common) do
      resource VpsAdmin::API::Resources::ClusterResource
      integer :value
    end

    params(:all) do
      id :id
      use :common
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List user cluster resource package contents'

      output(:object_list) do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict user_id: u.id
        allow
      end

      def query
        urp = ::UserClusterResourcePackage.where(with_restricted(
          id: params[:user_cluster_resource_package_id],
        )).take!

        ::ClusterResourcePackageItem.where(
          cluster_resource_package_id: urp.cluster_resource_package_id,
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
        restrict user_id: u.id
        allow
      end

      def prepare
        urp = ::UserClusterResourcePackage.where(with_restricted(
          id: params[:user_cluster_resource_package_id],
        )).take!

        @it = ::ClusterResourcePackageItem.where(
          cluster_resource_package_id: urp.cluster_resource_package_id,
          id: params[:item_id],
        ).take!
      end

      def exec
        @it
      end
    end
  end
end
