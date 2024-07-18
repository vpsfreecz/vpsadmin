module VpsAdmin::API::Resources
  class DnsTsigKey < HaveAPI::Resource
    model ::DnsTsigKey
    desc 'Manage DNS TSIG key transfers'

    params(:common) do
      resource User, value_label: :login
      string :name
      string :algorithm, default: 'hmac-256'
    end

    params(:all) do
      integer :id, label: 'ID'
      use :common
      string :secret
      datetime :created_at
      datetime :updated_at
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List DNS TSIG key'

      input do
        use :common, include: %i[user algorithm]
      end

      output(:object_list) do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict user_id: u.id
        allow
      end

      def query
        q = self.class.model.where(with_restricted)

        %i[user algorithm].each do |v|
          q = q.where(v => input[v]) if input.has_key?(v)
        end

        q
      end

      def count
        query.count
      end

      def exec
        with_includes(query).limit(input[:limit]).offset(input[:offset])
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      desc 'Show DNS TSIG key'

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict user_id: u.id
        allow
      end

      def prepare
        @key = self.class.model.find_by!(with_restricted(id: params[:dns_tsig_key_id]))
      end

      def exec
        @key
      end
    end

    class Create < HaveAPI::Actions::Default::Create
      desc 'Create a DNS TSIG key'

      input do
        use :common
        patch :algorithm, default: 'hmac-sha256', fill: true
      end

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict user_id: u.id
        input blacklist: %i[user]
        allow
      end

      def exec
        VpsAdmin::API::Operations::DnsTsigKey::Create.run(to_db_names(input))
      rescue ActiveRecord::RecordInvalid => e
        error('create failed', e.record.errors.to_hash)
      rescue ActiveRecord::RecordNotUnique => e
        error("key #{input[:name]} already exists")
      end
    end

    class Delete < HaveAPI::Actions::Default::Delete
      desc 'Delete DNS TSIG key'

      authorize do |u|
        allow if u.role == :admin
        restrict user_id: u.id
        allow
      end

      def exec
        key = self.class.model.find_by!(with_restricted(id: params[:dns_tsig_key_id]))
        VpsAdmin::API::Operations::DnsTsigKey::Destroy.run(key)
      rescue ActiveRecord::DeleteRestrictionError
        error("key #{key.name} is in use")
      rescue VpsAdmin::API::Exceptions::OperationError => e
        error(e.message)
      end
    end
  end
end
