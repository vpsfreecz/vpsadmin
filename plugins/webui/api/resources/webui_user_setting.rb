module VpsAdmin::API::Resources
  class WebuiUserSetting < HaveAPI::Resource
    desc 'Store web UI settings for the current user'
    model ::WebuiUserSetting

    params(:identity) do
      string :namespace
      string :key
    end

    params(:all) do
      id :id
      resource VpsAdmin::API::Resources::User, value_label: :login
      use :identity
      custom :value
      datetime :created_at
      datetime :updated_at
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List web UI settings for the current user'

      input do
        use :identity
      end

      output(:object_list) do
        use :all
      end

      authorize do |u|
        allow if u
      end

      def query
        q = ::WebuiUserSetting.where(user: current_user)

        q = q.where(namespace: input[:namespace]) if input.has_key?(:namespace)
        q = q.where(key: input[:key]) if input.has_key?(:key)

        q
      end

      def count
        query.count
      end

      def exec
        with_pagination(query.order(:namespace, :key))
      end
    end

    class Show < HaveAPI::Action
      desc 'Show a web UI setting'
      route '{namespace}/{key}'
      http_method :get

      output do
        use :all
      end

      authorize do |u|
        allow if u
      end

      def exec
        find_setting!
      end

      protected

      def find_setting!
        ::WebuiUserSetting.find_by!(
          user: current_user,
          namespace: path_params['namespace'],
          key: path_params['key']
        )
      end
    end

    class Set < HaveAPI::Action
      desc 'Create or update a web UI setting'
      route '{namespace}/{key}'
      http_method :put

      input do
        custom :value, required: true
      end

      output do
        use :all
      end

      authorize do |u|
        allow if u
      end

      def exec
        ::WebuiUserSetting.set!(
          user: current_user,
          namespace: path_params['namespace'],
          key: path_params['key'],
          value: input[:value]
        )
      rescue ActiveRecord::RecordInvalid => e
        error!('set failed', e.record.errors.to_hash)
      end
    end

    class Delete < HaveAPI::Action
      desc 'Delete a web UI setting'
      route '{namespace}/{key}'
      http_method :delete

      authorize do |u|
        allow if u
      end

      def exec
        ::WebuiUserSetting.find_by!(
          user: current_user,
          namespace: path_params['namespace'],
          key: path_params['key']
        ).destroy!
        ok!
      end
    end
  end
end
