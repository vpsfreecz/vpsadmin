module VpsAdmin::API::Resources
  class VpsUserData < HaveAPI::Resource
    desc 'Manage VPS user data'
    model ::VpsUserData

    params(:common) do
      resource User, value_label: :login
      string :label, label: 'Label'
      string :format, choices: ::VpsUserData.formats.keys.map(&:to_s)
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

      output(:object_list) do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict user_id: u.id
        allow
      end

      def query
        self.class.model.where(with_restricted)
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

        self.class.model.create!(input)
      rescue ActiveRecord::RecordInvalid => e
        error!('create failed', e.record.errors.to_hash)
      end
    end

    class Update < HaveAPI::Actions::Default::Update
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

        data.update!(input)
        data
      rescue ActiveRecord::RecordInvalid => e
        error!('update failed', e.record.errors.to_hash)
      end
    end

    class Delete < HaveAPI::Actions::Default::Delete
      desc 'Delete VPS user data'

      authorize do |_u|
        allow if u.role == :admin
        restrict user_id: u.id
        allow
      end

      def exec
        data = self.class.model.find_by!(with_restricted(
                                           user_id: params[:user_id],
                                           id: params[:vps_user_data_id]
                                         ))
        data.destroy!

        ok!
      end
    end
  end
end
