class VpsAdmin::API::Resources::UserNamespace < HaveAPI::Resource
  model ::UserNamespace
  desc 'Browse user namespaces'

  params(:all) do
    id :id, label: 'UserNS ID'
    resource VpsAdmin::API::Resources::User, value_label: :login
    integer :block_count, label: 'Block count'
    integer :size, label: 'Size'
  end

  class Index < HaveAPI::Actions::Default::Index
    desc 'List user namespaces'

    output(:object_list) do
      use :all
    end

    authorize do |u|
      allow if u.role == :admin
      restrict user_id: u.id
      allow
    end

    def query
      with_restricted(self.class.model)
    end

    def exec
      query.limit(params[:user][:limit]).offset(params[:user][:offset])
    end
  end

  class Show < HaveAPI::Actions::Default::Show
    output do
      use :all
    end

    authorize do |u|
      allow if u.role == :admin
      restrict user_id: u.id
      allow
    end

    def prepare
      @userns = with_restricted(self.class.model).find(params[:user_namespace_id])
    end

    def exec
      @userns
    end
  end
end
