module VpsAdmin::API::Resources
  class PasswordChangeLog < HaveAPI::Resource
    model ::PasswordChangeLog
    desc 'Browse password change history'

    SOURCE_CHOICES = {
      values: {
        authenticated: 'Signed-in change',
        forced_reset: 'Required password change',
        recovery: 'Password recovery',
        administrator: 'Administrator change',
        other: 'Other'
      }
    }.freeze

    params(:all) do
      id :id, label: 'ID'
      resource User, value_label: :login
      integer :user_session_id, label: 'User session ID', nullable: true
      resource UserSession, label: 'Session', value_label: :label, nullable: true
      string :client_ip_addr,
             label: 'Client IP address',
             db_name: :visible_client_ip_addr,
             nullable: true
      string :client_ip_ptr,
             label: 'Client IP PTR',
             db_name: :visible_client_ip_ptr,
             nullable: true
      string :user_agent,
             label: 'User agent',
             db_name: :visible_user_agent_string,
             nullable: true
      bool :user_session_owned_by_user,
           label: 'Session belongs to user',
           desc: 'Whether the affected user can open the initiating session'
      string :source, choices: SOURCE_CHOICES
      datetime :created_at, label: 'Changed at'
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List password changes'

      input do
        resource User, value_label: :login
        integer :user_session_id, label: 'User session ID', nullable: true
        string :source, choices: SOURCE_CHOICES
        patch :limit, default: 25, fill: true
      end

      output(:object_list) do
        use :all
      end

      authorize do |user|
        allow if user.role == :admin
        restrict user_id: user.id
        input blacklist: %i[user]
        output blacklist: %i[user_session]
        allow
      end

      def query
        q = ::PasswordChangeLog.where(with_restricted)
        q = q.where(user: input[:user]) if input[:user]
        q = q.where(user_session_id: input[:user_session_id]) if input[:user_session_id]
        q = q.where(source: input[:source]) if input[:source]
        q
      end

      def count
        query.count
      end

      def exec
        with_desc_pagination(with_includes(query))
          .includes(:user_agent, :user_session)
          .order('password_change_logs.id DESC')
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      desc 'Show a password change'

      output do
        use :all
      end

      authorize do |user|
        allow if user.role == :admin
        restrict user_id: user.id
        output blacklist: %i[user_session]
        allow
      end

      def prepare
        @password_change = ::PasswordChangeLog.find_by!(
          with_restricted(id: path_params['password_change_log_id'])
        )
      end

      def exec
        @password_change
      end
    end
  end
end
