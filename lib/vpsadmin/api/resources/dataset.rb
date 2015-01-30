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
      resource Dataset, label: 'Parent',
               name: :parent, value_label: :name
    end

    params(:all_properties) do
      VpsAdmin::API::DatasetProperties.to_params(self, :all)
    end

    params(:editable_properties) do
      VpsAdmin::API::DatasetProperties.to_params(self, :rw)
    end

    params(:all) do
      use :id
      use :common
      use :all_properties
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

      def query
        ::Dataset.joins(dataset_in_pools: [:pool]).where(with_restricted).where(
            pools: {role: [::Pool.roles[:hypervisor], ::Pool.roles[:primary]]}
        )
      end

      def count
        query.count
      end

      def exec
        ret = []

        query.includes(:dataset_properties).order('full_name').limit(input[:limit]).offset(input[:offset]).each do |ds|
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

      def prepare
        @ds = ::Dataset.find_by!(with_restricted(id: params[:dataset_id]))
      end

      def exec
        @ds
      end
    end

    class Create < HaveAPI::Actions::Default::Create
      desc 'Create a subdataset'

      input do
        string :name, label: 'Name', required: true
        resource Dataset, label: 'Parent dataset',
                 value_label: :full_name
        bool :automount, label: 'Automount',
             desc: 'Automatically mount newly created datasets under all its parents',
             default: false, fill: true
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
        end

        ::Dataset.create_new(
            input[:name].strip,
            input[:dataset],
            input[:automount]
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

    class Update < HaveAPI::Actions::Default::Update
      desc 'Update a dataset'

      input do
        use :editable_properties
      end

      authorize do |u|
        allow if u.role == :admin
        restrict user_id: u.id
        allow
      end

      def exec
        ds = ::Dataset.find_by!(with_restricted(id: params[:dataset_id]))

        properties = VpsAdmin::API::DatasetProperties.validate_params(input)
        ds.update_properties(properties)

        ok

      rescue VpsAdmin::API::Exceptions::PropertyInvalid => e
        error("property invalid: #{e.message}")
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

    class Inherit < HaveAPI::Action
      desc 'Inherit dataset property'
      route ':%{resource}_id/inherit'
      http_method :post

      input do
        string :property, label: 'Property',
               desc: 'Name of property to inherit from parent, multiple properties may be separated by a comma',
               required: true
      end

      authorize do |u|
        allow if u.role == :admin
        restrict user_id: u.id
        allow
      end

      def exec
        ds = ::Dataset.find_by!(with_restricted(id: params[:dataset_id]))

        if current_user.role != :admin && !ds.user_editable
          error('insufficient permission to inherit this property')
        end

        not_exists = []
        not_inheritable = []
        props = []

        input[:property].split(',').each do |p|
          s = p.to_sym

          if VpsAdmin::API::DatasetProperties.exists?(s)
            if VpsAdmin::API::DatasetProperties.property(s).inheritable? && VpsAdmin::API::DatasetProperties.property(s).editable?
              props << s

            else
              not_inheritable << s
            end

          else
            not_exists << s
          end
        end

        if !not_exists.empty?
          error("property does not exist: #{not_exists.join(',')}")

        elsif !not_inheritable.empty?
          error("property is not inheritable: #{not_inheritable.join(',')}")
        end

        ds.inherit_properties(props)
        ok
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

        def query
          ::Snapshot.joins(:dataset).where(
              with_restricted(dataset_id: params[:dataset_id])
          )
        end

        def count
          query.count
        end

        def exec
          query.order('created_at').limit(input[:limit]).offset(input[:offset])
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

      class Rollback < HaveAPI::Action
        desc 'Rollback to a snapshot'
        route ':%{resource}_id/rollback'
        http_method :post

        authorize do |u|
          allow if u.role == :admin
          restrict datasets: {user_id: u.id}
          allow
        end

        def exec
          snap = ::Snapshot.includes(:dataset).joins(:dataset).find_by!(with_restricted(
              dataset_id: params[:dataset_id],
              id: params[:snapshot_id]
          ))

          snap.dataset.rollback_snapshot(snap)
          ok
        end
      end
    end

    class Download < HaveAPI::Resource
      version 1
      route ':dataset_id/downloads'
      model ::SnapshotDownload
      desc 'Manage download links of dataset snapshots'

      params(:input) do
        resource VpsAdmin::API::Resources::Dataset::Snapshot, label: 'Snapshot',
                 value_label: :created_at
      end

      params(:all) do
        id :id
        use :input
      end

      class Index < HaveAPI::Actions::Default::Index
        output(:object_list) do
          use :all
        end

        authorize do |u|
          allow if u.role == :admin
          restrict datasets: {user: u}
          allow
        end

        def query
          ::SnapshotDownload.joins(snapshot: [:dataset]).where(with_restricted(
              datasets: {id: params[:dataset_id]}
          ))
        end

        def count
          query.count
        end

        def exec
          query.offset(input[:offset]).limit(input[:limit])
        end
      end

      class Show < HaveAPI::Actions::Default::Index
        resolve ->(dl){ [dl.snapshot.dataset_id, dl.id] }

        output do
          use :all
        end

        authorize do |u|
          allow if u.role == :admin
          restrict datasets: {user: u}
          allow
        end

        def prepare
          @dl = ::SnapshotDownload.joins(snapshot: [:dataset]).find_by!(with_restricted(
              datasets: {id: params[:dataset_id]},
              id: params[:download_id]
          ))
        end

        def exec
          @dl
        end
      end

      class Create < HaveAPI::Actions::Default::Create
        desc 'Download a snapshot'

        input do
          use :input
        end

        output do
          use :all
        end

        authorize do |u|
          allow if u.role == :admin
          restrict datasets: {user_id: u.id}
          allow
        end

        def exec
          snap = ::Snapshot.includes(:dataset).joins(:dataset).find_by!(with_restricted(
              dataset_id: params[:dataset_id],
              id: input[:snapshot].id
          ))

          if snap.snapshot_download_id
            error('this snapshot has already been made available for download')
          end

          snap.download
        end
      end

      class Delete < HaveAPI::Actions::Default::Delete
        desc 'Delete download link'

        authorize do |u|
          allow if u.role == :admin
          restrict datasets: {user_id: u.id}
          allow
        end

        def exec
          dl = ::SnapshotDownload.joins(snapshot: [:dataset]).find_by!(with_restricted(
              datasets: {id: params[:dataset_id]},
              id: params[:download_id]
          ))
          dl.destroy
          ok
        end
      end
    end
  end
end
