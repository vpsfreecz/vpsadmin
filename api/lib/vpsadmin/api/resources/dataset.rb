module VpsAdmin::API::Resources
  class Dataset < HaveAPI::Resource
    desc 'Manage datasets'
    model ::Dataset

    params(:id) do
      id :id
    end

    params(:common) do
      string :name, label: 'Name', db_name: :full_name
      # string :label, label: 'Label'
      resource Dataset, label: 'Parent',
               name: :parent, value_label: :name
      resource User, label: 'User', value_label: :login,
          desc: 'Dataset owner'
      resource Environment, label: 'Environment',
               desc: 'The environment in which the dataset is'
      integer :current_history_id
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

      input do
        resource User, label: 'User', value_label: :login,
                 desc: 'Dataset owner'
        resource VpsAdmin::API::Resources::Dataset, label: 'Subtree'
        string :role, label: 'Role', desc: 'Show only datasets of certain role',
            choices: ::Pool.roles.keys
        integer :to_depth, label: 'To depth', desc: 'Show only datasets to certain depth'
      end

      output(:object_list) do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict user_id: u.id
        input blacklist: %i(user)
        output blacklist: %i(sharenfs)
        allow
      end

      def query
        q = with_includes.joins(dataset_in_pools: [:pool]).where(with_restricted)
        q = q.subtree_of(input[:dataset]) if input[:dataset]

        if input[:role]
          q = q.where(pools: {role: ::Pool.roles[input[:role].to_sym]})

        else
          q = q.where(pools: {role: [::Pool.roles[:hypervisor], ::Pool.roles[:primary]]})
        end

        q = q.where(user: input[:user]) if input[:user]
        q = q.to_depth(input[:to_depth]) if input[:to_depth]

        q
      end

      def count
        query.count
      end

      def exec
        ret = []

        query.includes(
            :dataset_properties,
            dataset_in_pools: [pool: [node: [location: [:environment]]]]
        ).order('full_name').limit(input[:limit]).offset(input[:offset]).each do |ds|
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
        input blacklist: %i(sharenfs)
        output blacklist: %i(sharenfs)
        allow
      end

      def prepare
        @ds = with_includes.find_by!(with_restricted(id: params[:dataset_id]))
      end

      def exec
        @ds
      end
    end

    class Create < HaveAPI::Actions::Default::Create
      desc 'Create a subdataset'
      blocking true

      input do
        string :name, label: 'Name', required: true, load_validators: false, format: {
                rx: /\A[a-zA-Z0-9][a-zA-Z0-9_\-:\.\/]{0,254}\z/,
                message: "'%{value}' is not a valid dataset name"
            }
        resource Dataset, label: 'Parent dataset',
                 value_label: :full_name
        bool :automount, label: 'Automount',
             desc: 'Automatically mount newly created datasets under all its parents',
             default: false, fill: true
        use :editable_properties
      end

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict user_id: u.id
        input blacklist: %i(sharenfs)
        output blacklist: %i(sharenfs)
        allow
      end

      def exec
        if current_user.role != :admin && input[:dataset] && input[:dataset].user != current_user
          error('insufficient permission to create a dataset')

        elsif current_user.role != :admin && input[:dataset] && !input[:dataset].user_create
          error('access denied')
        end

        properties = VpsAdmin::API::DatasetProperties.validate_params(input)

        @chain, dataset = ::Dataset.create_new(
            input[:name].strip,
            input[:dataset],
            input[:automount],
            properties
        )
        dataset

      rescue VpsAdmin::API::Exceptions::PropertyInvalid => e
        error("property invalid: #{e.message}")

      rescue VpsAdmin::API::Exceptions::AccessDenied
        error('insufficient permission to create a dataset')

      rescue VpsAdmin::API::Exceptions::DatasetLabelDoesNotExist,
             VpsAdmin::API::Exceptions::DatasetAlreadyExists,
             VpsAdmin::API::Exceptions::DatasetNestingForbidden,
             VpsAdmin::API::Exceptions::InvalidRefquotaDataset,
             VpsAdmin::API::Exceptions::RefquotaCheckFailed => e
        error(e.message)

      rescue ActiveRecord::RecordInvalid => e
        error('create failed', e.record.errors.to_hash)
      end

      def state_id
        @chain.id
      end
    end

    class Update < HaveAPI::Actions::Default::Update
      desc 'Update a dataset'
      blocking true

      input do
        use :editable_properties
        bool :admin_override, label: 'Admin override',
             desc: 'Make it possible to assign more resource than the user actually has'
        string :admin_lock_type, label: 'Admin lock type', choices: %i(no_lock absolute not_less not_more),
            desc: 'How is the admin lock enforced'
      end

      authorize do |u|
        allow if u.role == :admin
        restrict user_id: u.id
        input blacklist: %i(sharenfs admin_override admin_lock_type)
        allow
      end

      def exec
        ds = ::Dataset.find_by!(with_restricted(id: params[:dataset_id]))
        ds.maintenance_check!(ds.primary_dataset_in_pool!.pool)

        properties = VpsAdmin::API::DatasetProperties.validate_params(input)
        @chain, _ = ds.update_properties(properties, input)

        ok

      rescue VpsAdmin::API::Exceptions::PropertyInvalid => e
        error("property invalid: #{e.message}")

      rescue VpsAdmin::API::Exceptions::InvalidRefquotaDataset,
             VpsAdmin::API::Exceptions::RefquotaCheckFailed => e
        error(e.message)

      rescue ActiveRecord::RecordInvalid => e
        error('update failed', e.record.errors.to_hash)
      end

      def state_id
        @chain.id
      end
    end

    class Delete < HaveAPI::Actions::Default::Delete
      desc 'Destroy a dataset with all its subdatasets and snapshots'
      blocking true

      authorize do |u|
        allow if u.role == :admin
        restrict user_id: u.id
        allow
      end

      def exec
        ds = ::Dataset.find_by!(with_restricted(id: params[:dataset_id]))

        if current_user.role != :admin && !ds.user_destroy
          error('insufficient permission to destroy this dataset')

        elsif ::Vps.exists?(dataset_in_pool: ds.primary_dataset_in_pool!)
          error('unable to delete, this dataset serves as a root FS for a VPS')
        end

        ds.maintenance_check!(ds.primary_dataset_in_pool!.pool)

        @chain, _ = ds.destroy
        ok

      rescue VpsAdmin::API::Exceptions::DatasetDoesNotExist => e
        error(e.message)
      end

      def state_id
        @chain.id
      end
    end

    class Inherit < HaveAPI::Action
      desc 'Inherit dataset property'
      route ':%{resource}_id/inherit'
      http_method :post
      blocking true

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

        ds.maintenance_check!(ds.primary_dataset_in_pool!.pool)

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

        @chain, _ = ds.inherit_properties(props)
        ok
      end

      def state_id
        @chain.id
      end
    end

    class Snapshot < HaveAPI::Resource
      route ':dataset_id/snapshots'
      model ::Snapshot
      desc 'Manage dataset snapshots'

      params(:all) do
        id :id
        resource Dataset, value_label: :name
        string :name
        string :label, label: 'Label'
        datetime :created_at # FIXME: this is not correct creation time
        integer :history_id
        resource VPS::Mount, value_label: :mountpoint
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
        blocking true

        input do
          use :all, include: %i(label)
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
          ds = ::Dataset.find_by!(with_restricted(id: params[:dataset_id]))
          ds.maintenance_check!(ds.primary_dataset_in_pool!.pool)

          max_snapshots = ds.max_snapshots

          if ds.snapshots.count >= max_snapshots
            error("cannot make more than #{max_snapshots} snapshots")
          end

          @chain, snap = ds.snapshot(input)
          snap.snapshot
        end

        def state_id
          @chain.id
        end
      end

      class Delete < HaveAPI::Actions::Default::Delete
        desc 'Destroy a snapshot'
        blocking true

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

          if snap.snapshot_in_pools.exists?('reference_count > 0')
            error('this snapshot cannot be destroyed as others are depending on it')

          elsif snap.dataset.dataset_in_pools.joins(:pool).where(
                    pools: {role: ::Pool.roles[:backup]}
                ).count > 0
            error('cannot destroy snapshot with backups')
          end

          snap.dataset.maintenance_check!(snap.dataset.primary_dataset_in_pool!.pool)

          @chain, _ = snap.destroy
          ok
        end

        def state_id
          @chain.id
        end
      end

      class Rollback < HaveAPI::Action
        desc 'Rollback to a snapshot'
        route ':%{resource}_id/rollback'
        http_method :post
        blocking true

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

          snap.dataset.maintenance_check!(snap.dataset.primary_dataset_in_pool!.pool)

          # Check if any snapshots on primary pool are mounted
          mnt = snap.dataset.snapshots.select(
              'snapshots.id, snapshots.name, mounts.id AS mnt_id, mounts.vps_id,'+
              'mounts.dst'
          ).joins(
              snapshot_in_pools: [
                  {dataset_in_pool: [:pool]},
                  :mounts
              ]
          ).where(
              pools: {
                  role: [
                      ::Pool.roles[:primary],
                      ::Pool.roles[:hypervisor]
                  ]
              }
          ).take

          if mnt
            error(
                "Please delete mount of snapshot #{snap.dataset.full_name}@#{mnt.name} "+
                "from VPS #{mnt.vps_id} at '#{mnt.dst}' (mount id #{mnt.mnt_id})"
            )
          end

          @chain, _ = snap.dataset.rollback_snapshot(snap)
          ok

        rescue VpsAdmin::API::Exceptions::SnapshotInUse => e
          error(e.message)
        end

        def state_id
          @chain.id
        end
      end
    end

    class Plan < HaveAPI::Resource
      route ':dataset_id/plans'
      model ::DatasetInPoolPlan
      desc 'Manage dataset plans'

      params(:common) do
        resource VpsAdmin::API::Resources::Environment::DatasetPlan,
                 name: :environment_dataset_plan,
                 required: true
      end

      params(:all) do
        id :id
        use :common
      end

      class Index < HaveAPI::Actions::Default::Index
        output(:object_list) do
          use :all
        end

        authorize do |u|
          allow if u.role == :admin
          restrict user: u
          allow
        end

        def query
          ds = ::Dataset.find_by!(with_restricted(id: params[:dataset_id]))
          ds.primary_dataset_in_pool!.dataset_in_pool_plans
        end

        def count
          query.count
        end

        def exec
          with_includes(query).includes(
              environment_dataset_plan: [:dataset_plan]
          ).offset(input[:offset]).limit(input[:limit])
        end
      end

      class Show < HaveAPI::Actions::Default::Show
        desc 'Show dataset plan'
        resolve ->(p){ [p.dataset_in_pool.dataset_id, p.id] }

        output do
          use :all
        end

        authorize do |u|
          allow if u.role == :admin
          restrict user: u
          allow
        end

        def prepare
          ds = ::Dataset.find_by!(with_restricted(id: params[:dataset_id]))
          @plan = ds.primary_dataset_in_pool!.dataset_in_pool_plans.find_by!(params[:plan_id])
        end

        def exec
          @plan
        end
      end

      class Create < HaveAPI::Actions::Default::Create
        desc 'Assign new dataset plan'

        input do
          use :common
        end

        output do
          use :all
        end

        authorize do |u|
          allow if u.role == :admin
          restrict user: u
          allow
        end

        def exec
          s = ::Dataset.find_by!(with_restricted(id: params[:dataset_id]))

          if !input[:environment_dataset_plan].user_add && current_user.role != :admin
            error('Insufficient permission')
          end

          s.primary_dataset_in_pool!.add_plan(input[:environment_dataset_plan])
        end
      end

      class Delete < HaveAPI::Actions::Default::Delete
        desc 'Remove dataset plan'

        authorize do |u|
          allow if u.role == :admin
          restrict user: u
          allow
        end

        def exec
          ds = ::Dataset.find_by!(with_restricted(id: params[:dataset_id]))
          dip =  ds.primary_dataset_in_pool!

          dip_plan = dip.dataset_in_pool_plans.find(params[:plan_id])

          unless dip_plan.environment_dataset_plan.user_remove
            error('Insufficient permission')
          end

          dip.del_plan(dip_plan)
          ok
        end
      end
    end

    class PropertyHistory < HaveAPI::Resource
      desc 'View property history'
      route ':dataset_id/property_history'
      model ::DatasetPropertyHistory

      params(:all) do
        id :id
        string :name
        integer :value
        datetime :created_at
      end

      class Index < HaveAPI::Actions::Default::Index
        input do
          datetime :from
          datetime :to
          string :name

          patch :limit, default: 25, fill: true
        end

        output(:object_list) do
          use :all
        end

        authorize do |u|
          allow if u.role == :admin
          restrict user: u
          allow
        end

        def query
          ds = ::Dataset.find_by!(with_restricted(id: params[:dataset_id]))
          props = ds.dataset_properties
          props = props.where(name: input[:name]) if input[:name]

          q = ::DatasetPropertyHistory.includes(:dataset_property).where(
              dataset_property_id: props.pluck(:id)
          )
          q = q.where('created_at >= ?', input[:from]) if input[:from]
          q = q.where('created_at <= ?', input[:to]) if input[:to]
          q
        end

        def count
          query.count
        end

        def exec
          query.order('created_at DESC').offset(input[:offset]).limit(input[:limit])
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

        def exec
          ds = ::Dataset.find_by!(with_restricted(id: params[:dataset_id]))
          ::DatasetPropertyHistory.includes(
              :dataset_property
          ).joins(
              :dataset_property
          ).find_by!(
              dataset_properties: {dataset_id: ds.id},
              id: params[:property_history_id]
          )
        end
      end
    end
  end
end
