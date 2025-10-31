module VpsAdmin::API::Resources
  class Os < HaveAPI::Resource
    model ::Os
    desc 'Manage operating systems'

    params(:common) do
      string :name
      string :label
    end

    params(:all) do
      id :id
      use :common
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List operating systems'

      output(:object_list) do
        use :all
      end

      authorize do |_u|
        allow
      end

      def query
        self.class.model.all
      end

      def count
        query.count
      end

      def exec
        with_pagination(query).order(:label)
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      output do
        use :all
      end

      authorize do |_u|
        allow
      end

      def prepare
        @os = self.class.model.find_by!(id: params[:operating_system_id])
      end

      def exec
        @os
      end
    end

    class Create < HaveAPI::Actions::Default::Create
      input do
        use :common
      end

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        self.class.model.create!(input)
      rescue ActiveRecord::RecordInvalid => e
        error!('create failed', e.record.errors.to_hash)
      end
    end

    class Update < HaveAPI::Actions::Default::Update
      input do
        use :common
      end

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        self.class.model.find(params[:operating_system_id]).update!(input)
      rescue ActiveRecord::RecordInvalid => e
        error!('update failed', e.record.errors.to_hash)
      end
    end

    class Delete < HaveAPI::Actions::Default::Delete
      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        self.class.model.find(params[:operating_system_id]).destroy!
        ok!
      end
    end
  end
end
