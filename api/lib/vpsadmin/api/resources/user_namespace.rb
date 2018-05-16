class VpsAdmin::API::Resources::UserNamespace < HaveAPI::Resource
  model ::UserNamespace
  desc 'Browse user namespaces'

  params(:all) do
    id :id, label: 'ID'
    resource VpsAdmin::API::Resources::User, value_label: :login
    integer :offset, label: 'Offset'
    integer :block_count, label: 'Block count'
    integer :size, label: 'Size'
  end

  params(:filters) do
    use :all, include: %i(user block_count size)
  end

  class Index < HaveAPI::Actions::Default::Index
    desc 'List user namespaces'

    input do
      use :filters
    end

    output(:object_list) do
      use :all
    end

    authorize do |u|
      allow if u.role == :admin
      restrict user_id: u.id
      input whitelist: %i(size)
      output whitelist: %i(id size)
      allow
    end

    def query
      q = self.class.model.where(with_restricted)

      %i(user block_count size).each do |v|
        q = q.where(v => input[v]) if input.has_key?(v)
      end

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
    output do
      use :all
    end

    authorize do |u|
      allow if u.role == :admin
      restrict user_id: u.id
      output whitelist: %i(id size)
      allow
    end

    def prepare
      @userns = self.class.model.find_by!(with_restricted(id: params[:user_namespace_id]))
    end

    def exec
      @userns
    end
  end
end
