module VpsAdmin::API::Resources
  class UserSession < HaveAPI::Resource
    model ::UserSession
    desc 'Browse user sessions'

    params(:all) do
      id :id
      resource User, value_label: :login
      string :label
      string :auth_type, label: 'Authentication type', choices: %w(basic token oauth2)
      string :api_ip_addr, label: 'IP Address'
      string :api_ip_ptr, label: 'IP PTR'
      string :client_ip_addr, label: 'Client IP Address'
      string :client_ip_ptr, label: 'Client IP PTR'
      string :user_agent, label: 'User agent', db_name: :user_agent_string
      string :client_version, label: 'Client version'
      string :scope, label: 'Scope', db_name: :scope_str
      string :token_fragment, label: 'Authentication token fragment'
      string :token_lifetime, label: 'Token lifetime', choices: ::UserSession.token_lifetimes.keys.map(&:to_s)
      integer :token_interval, label: 'Token interval'
      datetime :created_at, label: 'Created at'
      datetime :last_request_at, label: 'Last request at'
      integer :request_count, label: 'Request count'
      datetime :closed_at, label: 'Closed at'
      resource User, name: :admin, label: 'Admin', value_label: :login
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List user sessions'

      input do
        use :all, include: %i(user auth_type ip_addr api_ip_addr client_ip_addr
                              user_agent client_version token_fragment admin)
        string :ip_addr, label: 'IP Address', desc: 'Search both API and client IP address'
        string :state, choices: %w(all open closed), default: 'all', fill: true
        patch :limit, default: 25, fill: true
      end

      output(:object_list) do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        input blacklist: %i(admin)
        output blacklist: %i(admin)
        restrict user_id: u.id
        allow
      end

      def query
        q = ::UserSession.all.where(with_restricted)

        q = q.where(user: input[:user]) if input[:user] && current_user.role == :admin
        q = q.where(auth_type: input[:auth_type]) if input[:auth_type]

        case input[:state]
        when 'open'
          q = q.where(closed_at: nil)
        when 'closed'
          q = q.where.not(closed_at: nil)
        end

        if input[:ip_addr]
          q = q.where(
            'api_ip_addr LIKE ? OR client_ip_addr LIKE ?',
            input[:ip_addr], input[:ip_addr]
          )
        end

        q = q.where('api_ip_addr LIKE ?', input[:api_ip_addr]) if input[:api_ip_addr]
        q = q.where('client_ip_addr LIKE ?', input[:client_ip_addr]) if input[:client_ip_addr]

        if input[:user_agent]
          q = q.joins(:user_agents).where('agent LIKE ?', input[:user_agent])
        end

        q = q.where('client_version LIKE ?', input[:client_version]) if input[:client_version]
        q = q.where('token_str LIKE ?', "#{input[:token_fragment]}%") if input[:token_fragment]
        q = q.where(admin_id: input[:admin].id) if input[:admin]

        q
      end

      def count
        query.count
      end

      def exec
        with_includes(query)
          .includes(:user_agent)
          .order('created_at DESC')
          .limit(input[:limit])
          .offset(input[:offset])
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      desc 'Show a user session'

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        input blacklist: %i(admin)
        output blacklist: %i(admin)
        restrict user_id: u.id
        allow
      end

      def prepare
        @session = ::UserSession.find_by!(with_restricted(id: params[:user_session_id]))
      end

      def exec
        @session
      end
    end

    class Create < HaveAPI::Actions::Default::Create
      desc 'Create a new session for token authentication'

      input do
        use :all, include: %i(user scope token_lifetime token_interval label)
        patch :user, required: true
        patch :token_lifetime, required: true
        patch :scope, default: 'all', fill: true
      end

      output do
        use :all
        string :token_full
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        VpsAdmin::API::Operations::UserSession::NewTokenDetached.run(
          user: input[:user],
          admin: current_user,
          request: request,
          token_lifetime: input[:token_lifetime],
          token_interval: input[:token_interval],
          scope: input[:scope].split,
          label: input[:label],
        )

      rescue ActiveRecord::RecordInvalid
        error('failed to create user session')
      end
    end

    class Update < HaveAPI::Actions::Default::Update
      desc 'Update user session'

      input do
        use :all, include: %i(label)
        patch :label, required: true
      end

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict user_id: u.id
        allow
      end

      def exec
        user_session = ::UserSession.find_by!(with_restricted(id: params[:user_session_id]))
        user_session.update!(label: input[:label])

      rescue ActiveRecord::RecordInvalid
        error('failed to create user session')
      end
    end

    class Close < HaveAPI::Action
      desc 'Close user session, revoke access token'
      http_method :post
      route '{%{resource}_id}'

      authorize do |u|
        allow if u.role == :admin
        restrict user_id: u.id
        allow
      end

      def exec
        user_session = ::UserSession.find_by!(with_restricted(id: params[:user_session_id]))
        VpsAdmin::API::Operations::UserSession::Close.run(user_session)
        ok

      rescue ActiveRecord::RecordInvalid
        error('failed to close user session')
      end
    end
  end
end
