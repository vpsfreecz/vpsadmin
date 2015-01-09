module VpsAdmin::API::Resources
  class Dataset < HaveAPI::Resource
    desc 'Manage datasets'
    version 1
    model ::Dataset

    params(:id) do
      id :id
    end

    params(:common) do
      string :name, label: 'Name', db_name: :full_name
      # string :label, label: 'Label'
      string :mountpoint, label: 'Mountpoint', db_name: :hypervisor_mountpoint
      resource Dataset, label: 'Parent',
               name: :parent, value_label: :name
    end

    params(:all) do
      use :id
      use :common
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List datasets'

      output(:object_list) do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict user_id: u.id
        allow
      end

      def exec
        ret = []

        ::Dataset.where(with_restricted).order('full_name').each do |ds|
          ret << ds
        end

        ret
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      desc 'Show a dataset'

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict user_id: u.id
        allow
      end

      def exec
        ::Dataset.find_by!(with_restricted(id: params[:dataset_id]))
      end
    end

    class Create < HaveAPI::Actions::Default::Create
      desc 'Create a subdataset'

      input do
        string :name, label: 'Name', required: true
        string :mountpoint, label: 'Mountpoint',
               desc: 'Applies only for VPS subdatasets'
        resource Dataset, label: 'Parent dataset',
                 value_label: :full_name
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
        if current_user.role != :admin && input[:dataset] && input[:dataset].user != current_user
          error('insufficient permission to create a dataset')

        elsif current_user.role != :admin && input[:dataset] && !input[:dataset].user_create
          error('access denied')

        elsif input[:mountpoint] && input[:mountpoint].empty?
          error('invalid mountpoint: cannot be empty')
        end

        ::Dataset.create_new(
            input[:name].strip,
            input[:mountpoint] && input[:mountpoint].strip,
            input[:dataset]
        )

      rescue VpsAdmin::API::Exceptions::AccessDenied
        error('insufficient permission to create a dataset')

      rescue VpsAdmin::API::Exceptions::DatasetLabelDoesNotExist => e
        error(e.message)

      rescue VpsAdmin::API::Exceptions::DatasetAlreadyExists => e
        error(e.message)

      rescue ActiveRecord::RecordInvalid => e
        error('create failed', e.record.errors.to_hash)
      end
    end

    class Delete < HaveAPI::Actions::Default::Delete
      desc 'Destroy a dataset with all its subdatasets and snapshots'

      authorize do |u|
        allow if u.role == :admin
        restrict user_id: u.id
        allow
      end

      def exec
        ds = ::Dataset.find_by!(with_restricted(id: params[:dataset_id]))

        if current_user.role != :admin && !ds.user_destroy
          error('insufficient permission to destroy this dataset')
        end

        ds.destroy
        ok

      rescue VpsAdmin::API::Exceptions::DatasetDoesNotExist => e
        error(e.message)
      end
    end

    class Snapshot < HaveAPI::Resource
      version 1
      route ':dataset_id/snapshots'
      model ::Snapshot
      desc 'Manage dataset snapshots'

      params(:all) do
        id :id
        datetime :created_at # FIXME: this is not correct creation time
      end

      class Index < HaveAPI::Actions::Default::Index
        desc 'List snapshots'

        input do
          use :ds
        end

        output(:object_list) do
          use :all
        end

        authorize do |u|
          allow if u.role == :admin
          restrict datasets: {user_id: u.id}
          allow
        end

        def exec
          ::Snapshot.joins(:dataset).where(
              with_restricted(dataset_id: params[:dataset_id])
          ).order('created_at')
        end
      end

      class Show < HaveAPI::Actions::Default::Show
        desc 'Show snapshot'
        resolve ->(s){ [s.dataset_id, s.id] }

        output do
          use :all
        end

        authorize do |u|
          allow if u.role == :admin
          restrict datasets: {user_id: u.id}
          allow
        end

        def prepare
          @snapshot = ::Snapshot.joins(:dataset).find_by!(
              with_restricted(dataset_id: params[:dataset_id],
                              snapshots: {id: params[:snapshot_id]})
          )
        end

        def exec
          @snapshot
        end
      end

      class Create < HaveAPI::Actions::Default::Create
        desc 'Create snapshot'

        output do
          use :all
        end

        authorize do |u|
          allow if u.role == :admin
          restrict user_id: u.id
          allow
        end

        def exec
          ds = ::Dataset.find_by!(with_restricted(id: params[:dataset_id]))
          ds.snapshot
        end
      end
    end
  end
end
