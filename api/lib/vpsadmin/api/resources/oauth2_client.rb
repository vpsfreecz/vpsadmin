module VpsAdmin::API::Resources
  class Oauth2Client < HaveAPI::Resource
    model ::Oauth2Client
    desc 'Manage OAuth2 clients'

    params(:common) do
      string :name
      string :client_id
      string :redirect_uri
      string :authorization_start_uri,
             label: 'Authorization start URI',
             desc: 'Absolute HTTP(S) URI where authorization restarts after password recovery'
      bool :authorization_start_requires_user_action,
           label: 'Authorization start requires user action',
           desc: 'Show password recovery completion before opening an interactive authorization start URI'
      bool :is_default,
           label: 'Default client',
           desc: 'Use this client when an OAuth flow has no client context'
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
        with_pagination(with_includes(query))
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
        @client = self.class.model.find(path_params['oauth2_client_id'])
      end

      def exec
        @client
      end
    end

    class Create < HaveAPI::Actions::Default::Create
      desc 'Create an OAuth2 client'

      input do
        use :editable

        %i[name client_id client_secret redirect_uri].each do |param|
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
        client.save_with_default!
        client
      rescue ActiveRecord::RecordInvalid => e
        error!('create failed', e.record.errors.to_hash)
      rescue ActiveRecord::RecordNotUnique
        error!('create failed', is_default: ['has already been taken'])
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
        secret = input.delete(:client_secret)

        client = self.class.model.find(path_params['oauth2_client_id'])
        client.update_with_default!(input, client_secret: secret)
        client
      rescue ActiveRecord::RecordInvalid => e
        error!('update failed', e.record.errors.to_hash)
      rescue ActiveRecord::RecordNotUnique
        error!('update failed', is_default: ['has already been taken'])
      end
    end

    class Delete < HaveAPI::Actions::Default::Delete
      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        client = self.class.model.find(path_params['oauth2_client_id'])
        client.destroy_with_password_recoveries!
        ok!
      rescue ActiveRecord::RecordInvalid => e
        error!('update failed', e.record.errors.to_hash)
      end
    end
  end
end
