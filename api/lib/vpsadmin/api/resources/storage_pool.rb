module VpsAdmin::API::Resources
  class StoragePool < HaveAPI::Resource
    model ::StoragePool
    desc 'Manage libvirt storage pools'

    params(:common) do
      resource Node, value_label: :domain_name
      string :uuid
      string :name
      string :path
      datetime :created_at
      datetime :updated_at
    end

    params(:all) do
      id :id
      use :common
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List storage pools'

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
        with_pagination(query)
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def prepare
        @storage_pool = self.class.model.find_by!(id: params[:storage_pool_id])
      end

      def exec
        @storage_pool
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
        self.class.model.find(params[:storage_pool_id]).update!(input)
      rescue ActiveRecord::RecordInvalid => e
        error!('update failed', e.record.errors.to_hash)
      end
    end

    class Delete < HaveAPI::Actions::Default::Delete
      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        self.class.model.find(params[:storage_pool_id]).destroy!
        ok!
      end
    end
  end
end
