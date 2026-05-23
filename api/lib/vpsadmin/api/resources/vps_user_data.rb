module VpsAdmin::API::Resources
  class VpsUserData < HaveAPI::Resource
    desc 'Manage VPS user data'
    model ::VpsUserData

    params(:common) do
      resource User, value_label: :login
      string :label, label: 'Label'
      string :format
      text :content
    end

    params(:all) do
      id :id
      use :common
      datetime :created_at, label: 'Created at'
      datetime :updated_at, label: 'Updated at'
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List VPS user data'

      input do
        use :all, include: %i[user format]
      end

      output(:object_list) do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict user_id: u.id
        input blacklist: %i[user]
        allow
      end

      def query
        q = self.class.model.where(with_restricted)

        %i[user format].each do |v|
          q = q.where(v => input[v]) if input[v]
        end

        q
      end

      def count
        query.count
      end

      def exec
        with_pagination(query)
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      desc 'Show VPS user data'

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict user_id: u.id
        allow
      end

      def prepare
        @data = self.class.model.find_by!(with_restricted(id: params[:vps_user_data_id]))
      end

      def exec
        @data
      end
    end

    class Create < HaveAPI::Actions::Default::Create
      include VpsAdmin::API::Lifetimes::ActionHelpers

      desc 'Store VPS user data'

      input do
        use :common
      end

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        input whitelist: %i[label format content]
        allow
      end

      def exec
        input[:user] =
          if current_user.role == :admin
            input[:user] || current_user
          else
            current_user
          end

        object_state_check!(input[:user])

        self.class.model.create!(input)
      rescue ActiveRecord::RecordInvalid => e
        error!('create failed', e.record.errors.to_hash)
      end
    end

    class Update < HaveAPI::Actions::Default::Update
      include VpsAdmin::API::Lifetimes::ActionHelpers

      desc 'Update VPS user data'

      input do
        use :common, exclude: %i[user]
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
        ok! if input.empty?

        data = self.class.model.find_by!(with_restricted(id: params[:vps_user_data_id]))
        object_state_check!(data.user)

        data.update!(input)
        data
      rescue ActiveRecord::RecordInvalid => e
        error!('update failed', e.record.errors.to_hash)
      end
    end

    class Deploy < HaveAPI::Action
      include VpsAdmin::API::Maintainable::Check
      include VpsAdmin::API::Lifetimes::ActionHelpers

      desc 'Deploy user data to VPS'
      route '{%{resource}_id}/deploy'
      http_method :post
      blocking true

      input do
        resource VPS, value_label: :hostname, required: true
      end

      authorize do |u|
        allow if u.role == :admin
        restrict user_id: u.id
        allow
      end

      def exec
        data = self.class.model.find_by!(with_restricted(id: params[:vps_user_data_id]))
        error!('access denied') if input[:vps].user_id != data.user_id

        unless input[:vps].os_template.support_user_data?(data)
          error!(
            "OS template #{input[:vps].os_template.label} does not support #{data.format} user data"
          )
        end

        maintenance_check!(input[:vps])
        object_state_check!(input[:vps], input[:vps].user, data.user)

        @chain, = TransactionChains::Vps::DeployUserData.fire(input[:vps], data)
        ok!
      end

      def state_id
        @chain && @chain.id
      end
    end

    class Delete < HaveAPI::Actions::Default::Delete
      include VpsAdmin::API::Lifetimes::ActionHelpers

      desc 'Delete VPS user data'

      authorize do |u|
        allow if u.role == :admin
        restrict user_id: u.id
        allow
      end

      def exec
        data = self.class.model.find_by!(with_restricted(id: params[:vps_user_data_id]))
        object_state_check!(data.user)

        data.destroy!

        ok!
      end
    end
  end
end
