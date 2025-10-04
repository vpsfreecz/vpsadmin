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
      resource VPS, value_label: :hostname
      resource Export, value_label: :path
      resource DatasetExpansion, value_label: :created_at
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List datasets'

      input do
        resource User, label: 'User', value_label: :login,
                       desc: 'Dataset owner'
        resource VPS, label: 'VPS', value_label: :hostname
        resource VpsAdmin::API::Resources::Dataset, label: 'Subtree'
        resource Pool, name: :primary_pool, label: 'Primary pool', desc: 'Show only datasets on this pool'
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
        input blacklist: %i[user]
        output blacklist: %i[sharenfs]
        allow
      end

      def query
        q = with_includes.joins(dataset_in_pools: [:pool]).where(with_restricted)
        q = q.subtree_of(input[:dataset]) if input[:dataset]

        if input[:primary_pool]
          q = q.where(pools: { id: input[:primary_pool].id, role: 'primary' })
        end

        q = if input[:role]
              q.where(pools: { role: ::Pool.roles[input[:role].to_sym] })

            else
              q.where(pools: { role: [::Pool.roles[:hypervisor], ::Pool.roles[:primary]] })
            end

        q = q.where(user: input[:user]) if input[:user]
        q = q.where(vps: input[:vps]) if input.has_key?(:vps)
        q = q.to_depth(input[:to_depth]) if input[:to_depth]

        q
      end

      def count
        query.count
      end

      def exec
        ret = []

        with_pagination(query.includes(
          :dataset_properties,
          dataset_in_pools: [pool: [node: [location: [:environment]]]]
        ).order('full_name')).each do |ds|
          ret << ds
        end

        ret
      end
    end

    class FindByName < HaveAPI::Action
      desc 'Look up dataset by its name, possibly with a label'
      route 'find_by_name'
      http_method :get

      input do
        use :common, include: %i[user name]
      end

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        input blacklist: %i[user]
        output blacklist: %i[sharenfs]
        allow
      end

      def exec
        ok!(::VpsAdmin::API::Operations::Dataset::FindByName.run(
              current_user.role == :admin ? (input[:user] || current_user) : current_user,
              input[:name]
            ))
      rescue ActiveRecord::RecordNotFound
        error!('dataset not found')
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
        input blacklist: %i[sharenfs]
        output blacklist: %i[sharenfs]
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
          rx: %r{\A[a-zA-Z0-9][a-zA-Z0-9_\-:./]{0,254}\z},
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
        input blacklist: %i[sharenfs]
        output blacklist: %i[sharenfs]
        allow
      end

      def exec
        if current_user.role != :admin && input[:dataset] && input[:dataset].user != current_user
          error!('insufficient permission to create a dataset')

        elsif current_user.role != :admin && input[:dataset] && !input[:dataset].user_create
          error!('access denied')
        end

        properties = VpsAdmin::API::DatasetProperties.validate_params(input)

        @chain, dataset = VpsAdmin::API::Operations::Dataset::Create.run(
          input[:name].strip,
          input[:dataset],
          automount: input[:automount],
          properties:
        )
        dataset
      rescue VpsAdmin::API::Exceptions::PropertyInvalid => e
        error!("property invalid: #{e.message}")
      rescue VpsAdmin::API::Exceptions::AccessDenied
        error!('insufficient permission to create a dataset')
      rescue VpsAdmin::API::Exceptions::DatasetLabelDoesNotExist,
             VpsAdmin::API::Exceptions::DatasetAlreadyExists,
             VpsAdmin::API::Exceptions::DatasetNestingForbidden,
             VpsAdmin::API::Exceptions::InvalidRefquotaDataset,
             VpsAdmin::API::Exceptions::RefquotaCheckFailed => e
        error!(e.message)
      rescue ActiveRecord::RecordInvalid => e
        error!('create failed', e.record.errors.to_hash)
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
        string :admin_lock_type, label: 'Admin lock type', choices: %i[no_lock absolute not_less not_more],
                                 desc: 'How is the admin lock enforced'
      end

      authorize do |u|
        allow if u.role == :admin
        restrict user_id: u.id
        input blacklist: %i[sharenfs admin_override admin_lock_type]
        allow
      end

      def exec
        ds = ::Dataset.find_by!(with_restricted(id: params[:dataset_id]))
        ds.maintenance_check!(ds.primary_dataset_in_pool!.pool)

        properties = VpsAdmin::API::DatasetProperties.validate_params(input)

        @chain = VpsAdmin::API::Operations::Dataset::UpdateProperties.run(
          ds,
          properties,
          input
        )

        ok!
      rescue VpsAdmin::API::Exceptions::PropertyInvalid => e
        error!("property invalid: #{e.message}")
      rescue VpsAdmin::API::Exceptions::InvalidRefquotaDataset,
             VpsAdmin::API::Exceptions::RefquotaCheckFailed => e
        error!(e.message)
      rescue ActiveRecord::RecordInvalid => e
        error!('update failed', e.record.errors.to_hash)
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
          error!('insufficient permission to destroy this dataset')

        elsif ::Vps.exists?(dataset_in_pool: ds.primary_dataset_in_pool!)
          error!('unable to delete, this dataset serves as a root FS for a VPS')
        end

        ds.maintenance_check!(ds.primary_dataset_in_pool!.pool)

        @chain, = ds.destroy
        ok!
      rescue VpsAdmin::API::Exceptions::DatasetDoesNotExist => e
        error!(e.message)
      end

      def state_id
        @chain.id
      end
    end

    class Inherit < HaveAPI::Action
      desc 'Inherit dataset property'
      route '{%{resource}_id}/inherit'
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

        error!('insufficient permission to inherit this property') if current_user.role != :admin && !ds.user_editable

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
          error!("property does not exist: #{not_exists.join(',')}")

        elsif !not_inheritable.empty?
          error!("property is not inheritable: #{not_inheritable.join(',')}")
        end

        @chain, = TransactionChains::Dataset::Inherit.fire(ds.primary_dataset_in_pool!, props)
        ok!
      end

      def state_id
        @chain.id
      end
    end

    class Migrate < HaveAPI::Action
      desc 'Migrate dataset to another pool'
      route '{%{resource}_id}/migrate'
      http_method :post
      blocking true

      input do
        resource VpsAdmin::API::Resources::Pool, label: 'Pool',
                                                 required: true
        resource VpsAdmin::API::Resources::VPS, name: :maintenance_window_vps, label: 'VPS maintenance window',
                                                desc: 'Migrate the dataset within the nearest maintenance window of VPS'
        bool :restart_vps, label: 'Restart VPS', desc: 'Restart VPSes where migrated exports are mounted', default: false, fill: true
        integer :finish_weekday, label: 'Finish weekday',
                                 desc: 'Prepare the migration and finish it on this day',
                                 number: { min: 0, max: 6 }
        integer :finish_minutes, label: 'Finish minutes',
                                 desc: 'Number of minutes from midnight of start_weekday after which the migration is done',
                                 number: { min: 0, max: (24 * 60) - 30 }
        bool :optional_maintenance_window, label: 'Optional maintenance window',
                                           desc: 'Use maintenance window only if the dataset has any exports',
                                           default: true, fill: true
        bool :cleanup_data, label: 'Cleanup data',
                            desc: 'Remove dataset from the source pool',
                            default: true, fill: true
        bool :send_mail, label: 'Send e-mails',
                         desc: 'Inform the dataset owner about migration progress',
                         default: true, fill: true
        string :reason
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        ds = ::Dataset.find(params[:dataset_id])
        dip = ds.primary_dataset_in_pool!

        if dip.pool == input[:pool]
          error!('the dataset already is on this pool')

        elsif dip.pool.role != 'primary'
          error!('source pool is not primary')

        elsif input[:pool].role != 'primary'
          error!('target pool is not primary')

        elsif ds.parent
          error!('only top-level datasets can be migrated')

        elsif input[:maintenance_window_vps] && input[:maintenance_window_vps].user_id != ds.user_id
          error!('access denied to maintenance window VPS')
        end

        if (input[:finish_weekday] || input[:finish_minutes]) \
          && (!input[:finish_weekday] || !input[:finish_minutes])
          error!('invalid finish configuration', {
                  finish_weekday: ['must be set together with finish_minutes'],
                  finish_minutes: ['must be set together with finish_weekday']
                })
        end

        if input[:maintenance_window_vps] && (input[:finish_weekday] || input[:finish_minutes])
          error!('invalid finish configuration', {
                  maintenance_window_vps: ['conflicts with finish_weekday and finish_minutes']
                })
        end

        @chain, = TransactionChains::Dataset::Migrate.fire2(
          args: [dip, input[:pool]],
          kwargs: {
            send_mail: input[:send_mail],
            reason: input[:reason],
            cleanup_data: input[:cleanup_data],
            restart_vps: input[:restart_vps],
            maintenance_window_vps: input[:maintenance_window_vps],
            finish_weekday: input[:finish_weekday],
            finish_minutes: input[:finish_minutes],
            optional_maintenance_window: input[:optional_maintenance_window]
          }
        )
        ok!
      end

      def state_id
        @chain.id
      end
    end

    class Snapshot < HaveAPI::Resource
      route '{dataset_id}/snapshots'
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
        resource Export, value_label: :path
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
          restrict datasets: { user_id: u.id }
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
          with_pagination(query.order('created_at'))
        end
      end

      class Show < HaveAPI::Actions::Default::Show
        desc 'Show snapshot'
        resolve ->(s) { [s.dataset_id, s.id] }

        output do
          use :all
        end

        authorize do |u|
          allow if u.role == :admin
          restrict datasets: { user_id: u.id }
          allow
        end

        def prepare
          @snapshot = ::Snapshot.joins(:dataset).find_by!(
            with_restricted(dataset_id: params[:dataset_id],
                            snapshots: { id: params[:snapshot_id] })
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
          use :all, include: %i[label]
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

          error!("cannot make more than #{max_snapshots} snapshots") if ds.snapshots.count >= max_snapshots

          dip = ds.primary_dataset_in_pool!

          if dip.pool.role == 'hypervisor'
            vps = Vps.find_by!(dataset_in_pool: dip.dataset.root.primary_dataset_in_pool!)
            maintenance_check!(vps)
          end

          @chain, snap = TransactionChains::Dataset::Snapshot.fire(dip, input)

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
          restrict datasets: { user_id: u.id }
          allow
        end

        def exec
          snap = ::Snapshot.includes(:dataset).joins(:dataset).find_by!(with_restricted(
                                                                          dataset_id: params[:dataset_id],
                                                                          id: params[:snapshot_id]
                                                                        ))

          if snap.snapshot_in_pools.exists?('reference_count > 0')
            error!('this snapshot cannot be destroyed as others are depending on it')

          elsif snap.dataset.dataset_in_pools.joins(:pool).where(
            pools: { role: ::Pool.roles[:backup] }
          ).count > 0
            error!('cannot destroy snapshot with backups')
          end

          snap.dataset.maintenance_check!(snap.dataset.primary_dataset_in_pool!.pool)

          @chain, = TransactionChains::Snapshot::Destroy.fire(snap)
          ok!
        end

        def state_id
          @chain.id
        end
      end

      class Rollback < HaveAPI::Action
        desc 'Rollback to a snapshot'
        route '{%{resource}_id}/rollback'
        http_method :post
        blocking true

        authorize do |u|
          allow if u.role == :admin
          restrict datasets: { user_id: u.id }
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
            'snapshots.id, snapshots.name, mounts.id AS mnt_id, mounts.vps_id,' \
            'mounts.dst'
          ).joins(
            snapshot_in_pools: [
              { dataset_in_pool: [:pool] },
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
            error!(
              "Please delete mount of snapshot #{snap.dataset.full_name}@#{mnt.name} " \
              "from VPS #{mnt.vps_id} at '#{mnt.dst}' (mount id #{mnt.mnt_id})"
            )
          end

          dip = snap.dataset.primary_dataset_in_pool!

          @chain, =
            if dip.pool.role == 'hypervisor'
              vps = Vps.find_by!(dataset_in_pool: dip.dataset.root.primary_dataset_in_pool!)
              maintenance_check!(vps)

              TransactionChains::Vps::Restore.fire(vps, snap)
            else
              TransactionChains::Dataset::Rollback.fire(dip, snap)
            end

          ok!
        rescue VpsAdmin::API::Exceptions::SnapshotInUse => e
          error!(e.message)
        end

        def state_id
          @chain.id
        end
      end
    end

    class Plan < HaveAPI::Resource
      route '{dataset_id}/plans'
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
          with_pagination(with_includes(query).includes(
                            environment_dataset_plan: [:dataset_plan]
                          ))
        end
      end

      class Show < HaveAPI::Actions::Default::Show
        desc 'Show dataset plan'
        resolve ->(p) { [p.dataset_in_pool.dataset_id, p.id] }

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

          error!('Insufficient permission') if !input[:environment_dataset_plan].user_add && current_user.role != :admin

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
          dip = ds.primary_dataset_in_pool!

          dip_plan = dip.dataset_in_pool_plans.find(params[:plan_id])

          if !dip_plan.environment_dataset_plan.user_remove && current_user.role != :admin
            error!('Insufficient permission')
          end

          dip.del_plan(dip_plan)
          ok!
        end
      end
    end

    class PropertyHistory < HaveAPI::Resource
      desc 'View property history'
      route '{dataset_id}/property_history'
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
          with_pagination(query.order('created_at DESC'))
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
            dataset_properties: { dataset_id: ds.id },
            id: params[:property_history_id]
          )
        end
      end
    end
  end
end
