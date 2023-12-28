module VpsAdmin::API::Resources
  class Oauth2Client < HaveAPI::Resource
    model ::Oauth2Client
    desc 'Manage OAuth2 clients'

    params(:common) do
      string :name
      string :client_id
      string :redirect_uri
      string :access_token_lifetime, choices: ::Oauth2Client.access_token_lifetimes.keys.map(&:to_s)
      integer :access_token_seconds
      integer :refresh_token_seconds
      bool :issue_refresh_token
      bool :allow_single_sign_on
    end

    params(:editable) do
      use :common
      string :client_secret
    end

    params(:all) do
      id :id
      use :common
      datetime :created_at
      datetime :updated_at
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List OAuth2 clients'

      output(:object_list) do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def query
        self.class.model.all
      end

      def count
        query.count
      end

      def exec
        with_includes(query).limit(input[:limit]).offset(input[:offset])
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      desc 'Show OAuth2 client'

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def prepare
        @client = self.class.model.find(params[:oauth2_client_id])
      end

      def exec
        @client
      end
    end

    class Create < HaveAPI::Actions::Default::Create
      desc 'Create an OAuth2 client'

      input do
        use :editable

        %i(name client_id client_secret redirect_uri).each do |param|
          patch param, required: true
        end
      end

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        secret = input.delete(:client_secret)

        client = ::Oauth2Client.new(input)
        client.set_secret(secret)
        client.save!
        client

      rescue ActiveRecord::RecordInvalid => e
        error('create failed', e.record.errors.to_hash)
      end
    end

    class Update < HaveAPI::Actions::Default::Update
      input do
        use :editable
      end

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        secret = input.delete(:secret)

        client = self.class.model.find(params[:oauth2_client_id])
        client.set_secret(secret) if secret
        client.assign_attributes(input)
        client.save!
        client

      rescue ActiveRecord::RecordInvalid => e
        error('update failed', e.record.errors.to_hash)
      end
    end

    class Delete < HaveAPI::Actions::Default::Delete
      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        client = self.class.model.find(params[:oauth2_client_id])
        client.destroy!
        ok

      rescue ActiveRecord::RecordInvalid => e
        error('update failed', e.record.errors.to_hash)
      end
    end
  end
end
