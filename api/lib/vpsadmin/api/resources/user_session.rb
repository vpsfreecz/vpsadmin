module VpsAdmin::API::Resources
  class UserSession < HaveAPI::Resource
    model ::UserSession
    desc 'Browse user sessions'

    params(:all) do
      id :id
      resource User, value_label: :login
      string :auth_type, label: 'Authentication type', choices: %i(basic token)
      string :api_ip_addr, label: 'IP Address'
      string :api_ip_ptr, label: 'IP PTR'
      string :client_ip_addr, label: 'Client IP Address'
      string :client_ip_ptr, label: 'Client IP PTR'
      string :user_agent, label: 'User agent'
      string :client_version, label: 'Client version'
      resource SessionToken, label: 'Authentication token'
      string :session_token_str, label: 'Authentication token',
        db_name: :session_token_str
      datetime :created_at, label: 'Created at'
      datetime :last_request_at, label: 'Last request at'
      datetime :closed_at, label: 'Closed at'
      resource User, name: :admin, label: 'Admin', value_label: :login
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List user sessions'

      input do
        use :all, include: %i(user auth_type ip_addr api_ip_addr client_ip_addr
                              user_agent client_version auth_token_str admin)
        string :ip_addr, label: 'IP Address', desc: 'Search both API and client IP address'
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
        q = q.where('session_token_str LIKE ?', input[:auth_token_str]) if input[:auth_token_str]
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
  end
end
