module VpsAdmin::API::Resources
  class MetricsAccessToken < HaveAPI::Resource
    model ::MetricsAccessToken
    desc 'Manage /metrics endpoint access tokens'

    params(:all) do
      id :id
      resource User, value_label: :login
      string :access_token, label: 'Access token'
      string :metric_prefix,
             label: 'Metric prefix',
             desc: 'Prefix added to all metrics',
             default: 'vpsadmin_',
             fill: true
      integer :use_count, label: 'Use count'
      datetime :last_use, label: 'Last use'
      datetime :created_at
      datetime :updated_at
    end

    class Index < HaveAPI::Actions::Default::Index
      input do
        resource User, value_label: :login
      end

      output(:object_list) do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict user: u
        input blacklist: %i[user]
        allow
      end

      def query
        q = self.class.model.where(with_restricted)
        q = q.where(user: input[:user]) if input[:user]
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
      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict user: u
        allow
      end

      def prepare
        @token = self.class.model.find_by(with_restricted(id: params[:metrics_access_token_id]))
      end

      def exec
        @token
      end
    end

    class Create < HaveAPI::Actions::Default::Create
      desc 'Create a new access token'

      input do
        use :all, include: %i[user metric_prefix]
      end

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        input blacklist: %i[user]
        allow
      end

      def exec
        target_user =
          if current_user.role == :admin && input[:user]
            input[:user]
          else
            current_user
          end

        ::MetricsAccessToken.create_for!(target_user, input[:metric_prefix])
      end
    end

    class Delete < HaveAPI::Actions::Default::Delete
      desc 'Delete access token'

      authorize do |u|
        allow if u.role == :admin
        restrict user: u
        allow
      end

      def exec
        token = self.class.model.find_by(with_restricted(id: params[:metrics_access_token_id]))
        token.destroy!
        ok!
      end
    end
  end
end
