module VpsAdmin::API
  module DatasetPlans
    # Register and store of properties.
    module Registrator
      def self.plan(name, label: nil, desc: nil, keep_empty_group_snapshots: false, &)
        @plans ||= {}
        @plans[name] = Plan.new(name, label, desc, keep_empty_group_snapshots:, &)
      end

      def self.plans
        @plans
      end
    end

    class Executor
      def initialize(plan, confirmation, definition)
        @env_plan = plan
        @confirm = confirmation
        @definition = definition
      end

      def add_group_snapshot(dip, min, hour, day, month, dow)
        schedule = schedule_attributes(min, hour, day, month, dow)
        action = group_action(dip)

        if @definition.keep_empty_group_snapshots && !action
          raise Exceptions::OperationError, 'Shared snapshot template is missing'
        end

        task_for!(action, schedule:) if action

        if action && action.group_snapshots.where(dataset_in_pool: dip).exists?
          raise Exceptions::OperationError, 'Snapshot membership already exists without this plan membership'
        end

        unless action
          action = ::DatasetAction.create!(
            pool_id: dip.pool_id,
            action: ::DatasetAction.actions[:group_snapshot],
            dataset_plan: @env_plan.dataset_plan
          )

          confirm(:just_create, action)

          task = ::RepeatableTask.create!(
            class_name: action.class.name,
            table_name: action.class.table_name,
            row_id: action.id,
            **schedule
          )

          confirm(:just_create, task)
        end

        grp = ::GroupSnapshot.create!(
          dataset_in_pool: dip,
          dataset_action: action
        )

        confirm(:just_create, grp)
      end

      def verify_group_snapshot(dip, min, hour, day, month, dow)
        action = group_action(dip)
        raise Exceptions::OperationError, 'Shared snapshot template is missing' unless action

        task_for!(action, schedule: schedule_attributes(min, hour, day, month, dow))
        members = action.group_snapshots.where(dataset_in_pool: dip).lock.limit(2).to_a
        raise Exceptions::OperationError, 'Snapshot membership is missing or ambiguous' unless members.one?

        check_pending!(members)
      end

      def del_group_snapshot(dip, min, hour, day, month, dow)
        action = group_action(dip)
        raise Exceptions::OperationError, 'Snapshot action is missing' unless action

        members = action.group_snapshots.where(dataset_in_pool: dip).lock.limit(2).to_a
        raise Exceptions::OperationError, 'Snapshot membership is missing or ambiguous' unless members.one?

        gsnap = members.first
        check_pending!([gsnap, action])
        orphan_action = !@definition.keep_empty_group_snapshots && !action.group_snapshots.where.not(id: gsnap.id).exists?
        task = task_for!(action, schedule: schedule_attributes(min, hour, day, month, dow))

        if confirm?
          confirm(:just_destroy, gsnap)
          confirm(:just_destroy, task) if orphan_action
          confirm(:just_destroy, action) if orphan_action
        else
          gsnap.destroy!

          if orphan_action
            task&.destroy!
            action.destroy!
          end
        end
      end

      def add_backup(dip, min, hour, day, month, dow)
        schedule = schedule_attributes(min, hour, day, month, dow)
        plan = ::DatasetInPoolPlan.find_by!(
          environment_dataset_plan: @env_plan,
          dataset_in_pool: dip
        )

        dst_dip = backup_destination!(dip)

        action = ::DatasetAction.create!(
          src_dataset_in_pool: dip,
          dst_dataset_in_pool: dst_dip,
          dataset_in_pool_plan: plan,
          action: ::DatasetAction.actions[:backup]
        )

        confirm(:just_create, action)

        task = ::RepeatableTask.create!(
          class_name: action.class.name,
          table_name: action.class.table_name,
          row_id: action.id,
          **schedule
        )

        confirm(:just_create, task)
      end

      def verify_backup(dip, min, hour, day, month, dow)
        plan = ::DatasetInPoolPlan.find_by!(environment_dataset_plan: @env_plan, dataset_in_pool: dip)
        actions = ::DatasetAction.where(dataset_in_pool_plan: plan, action: :backup).lock.limit(2).to_a
        raise Exceptions::OperationError, 'Backup action is missing or ambiguous' unless actions.one?

        action = actions.first
        unless action.src_dataset_in_pool_id == dip.id && action.dst_dataset_in_pool_id == backup_destination!(dip).id
          raise Exceptions::OperationError, 'Backup action has a conflicting destination'
        end

        check_pending!([action])
        task_for!(action, schedule: schedule_attributes(min, hour, day, month, dow))
      end

      def del_backup(dip, min, hour, day, month, dow)
        plan = ::DatasetInPoolPlan.find_by!(
          environment_dataset_plan: @env_plan,
          dataset_in_pool: dip
        )

        actions = ::DatasetAction.where(
          dataset_in_pool_plan: plan,
          action: ::DatasetAction.actions[:backup]
        ).lock.to_a
        if @definition.keep_empty_group_snapshots && !actions.one?
          raise Exceptions::OperationError, 'Backup action is missing or ambiguous'
        end

        actions.each do |a|
          unless a.src_dataset_in_pool_id == dip.id
            raise Exceptions::OperationError, 'Backup action has a conflicting source'
          end

          task = task_for!(a, schedule: schedule_attributes(min, hour, day, month, dow))
          check_pending!([a])

          if confirm?
            confirm(:just_destroy, task)
            confirm(:just_destroy, a)

          else
            task.destroy!
            a.destroy!
          end
        end
      end

      def confirm(type, *)
        return unless @confirm

        @confirm.send(type, *)
      end

      def confirm?
        @confirm ? true : false
      end

      private

      def schedule_attributes(minute, hour, day, month, weekday)
        ::VpsAdmin::Scheduler::CronTask.new(
          id: 0, class_name: 'DatasetAction', row_id: 0,
          minute:, hour:, day:, month:, weekday:
        )
        { minute:, hour:, day_of_month: day, month:, day_of_week: weekday }.transform_values(&:to_s)
      end

      def group_action(dip)
        actions = ::DatasetAction.where(pool_id: dip.pool_id, action: :group_snapshot,
                                        dataset_plan: @env_plan.dataset_plan).lock.limit(2).to_a
        raise Exceptions::OperationError, 'Shared snapshot template is ambiguous' if actions.length > 1

        check_pending!(actions)
        action = actions.first
        if action && @definition.keep_empty_group_snapshots &&
           (action.dataset_in_pool_plan_id || action.src_dataset_in_pool_id || action.dst_dataset_in_pool_id ||
            action.snapshot_id || action.recursive)
          raise Exceptions::OperationError, 'Shared snapshot template has incompatible fields'
        end

        action
      end

      def task_for!(action, schedule: nil)
        tasks = ::RepeatableTask.where(class_name: action.class.name, table_name: action.class.table_name,
                                       row_id: action.id).lock.limit(2).to_a
        raise Exceptions::OperationError, 'Action task is missing or ambiguous' unless tasks.one?

        task = tasks.first
        check_pending!([task])
        if schedule && task.attributes.slice(*schedule.keys.map(&:to_s)) != schedule.transform_keys(&:to_s)
          raise Exceptions::OperationError, 'Action task has an incompatible schedule'
        end

        task
      end

      def backup_destination!(dip)
        eligible = dip.dataset.dataset_in_pools.joins(:pool).where(pools: { role: :backup, is_open: true })
        destinations = if @definition.keep_empty_group_snapshots
                         eligible.limit(2).to_a
                       else
                         [eligible.take!]
                       end
        raise Exceptions::OperationError, 'Backup destination is missing or ambiguous' unless destinations.one?

        check_pending!(destinations)
        destinations.first
      end

      def check_pending!(records)
        @definition.check_pending_confirmations!(records, confirmation: @confirm)
      end
    end

    # Represents a single dataset plan.
    class Plan
      class BlockEnv
        attr_reader :direction

        def initialize(direction, plan, definition, confirmation = nil)
          @direction = direction
          @plan = plan
          @definition = definition
          @confirmation = confirmation
        end

        def group_snapshot(dip, *)
          task(:group_snapshot, dip, *)
        end

        def backup(dip, *)
          task(:backup, dip, *)
        end

        protected

        def task(name, *)
          @exec ||= Executor.new(@plan, @confirmation, @definition)
          @exec.method("#{@direction}_#{name}").call(*)
        end
      end

      attr_reader :name, :desc, :keep_empty_group_snapshots

      def initialize(name, label, desc, keep_empty_group_snapshots: false, &block)
        unless [true, false].include?(keep_empty_group_snapshots)
          raise ArgumentError, 'keep_empty_group_snapshots must be a boolean'
        end

        @name = name
        @label = label
        @desc = desc
        @block = block
        @keep_empty_group_snapshots = keep_empty_group_snapshots
      end

      def label(l = nil)
        if l
          @label = l
        else
          @label
        end
      end

      def register(dip, confirmation: nil)
        plan = nil

        with_configuration_lock do
          env_ds_plan = env_dataset_plan(dip)
          check_source!(dip, confirmation:)

          existing = ::DatasetInPoolPlan.where(environment_dataset_plan: env_ds_plan, dataset_in_pool: dip).lock.limit(2).to_a
          check_pending_confirmations!(existing, confirmation:)
          if @keep_empty_group_snapshots && existing.any?
            raise Exceptions::OperationError, 'Plan membership is ambiguous' unless existing.one?

            BlockEnv.new(:verify, env_ds_plan, self, confirmation).instance_exec(dip, &@block)
            plan = existing.first
            next
          end

          plan = ::DatasetInPoolPlan.create!(
            environment_dataset_plan: env_ds_plan,
            dataset_in_pool: dip
          )

          confirmation.just_create(plan) if confirmation

          BlockEnv.new(:add, env_ds_plan, self, confirmation).instance_exec(dip, &@block)
        end

        plan
      end

      def unregister(dip, confirmation: nil)
        with_configuration_lock do
          env_ds_plan = env_dataset_plan(dip)
          check_source!(dip, confirmation:)

          plan = ::DatasetInPoolPlan.find_by!(
            environment_dataset_plan: env_ds_plan,
            dataset_in_pool: dip
          ).tap(&:lock!)
          check_pending_confirmations!([plan], confirmation:)
          BlockEnv.new(:del, env_ds_plan, self, confirmation).instance_exec(dip, &@block)

          if confirmation
            confirmation.just_destroy(plan)
          else
            plan.destroy!
          end
        end
      end

      # Keep this order for registration, template provisioning and retirement.
      def with_configuration_lock
        ::DatasetPlan.transaction(requires_new: true) do
          ::StorageMutationAdmission.check!
          dataset_plan.lock!
          unless ::DatasetPlan.where(name: @name).limit(2).to_a.one?
            raise Exceptions::OperationError, 'Dataset plan definition is ambiguous'
          end

          yield dataset_plan
        end
      end

      def check_pending_confirmations!(records, confirmation: nil)
        chain_id = confirmation.transaction_chain_id if confirmation.respond_to?(:transaction_chain_id)
        records.each do |record|
          pending = ::TransactionConfirmation.where(done: 0, table_name: record.class.table_name,
                                                    row_pks: { 'id' => record.id })
          if chain_id
            own_transactions = ::Transaction.where(transaction_chain_id: chain_id).select(:id)
            pending = pending.where.not(transaction_id: own_transactions).or(
              pending.where(confirm_type: %i[destroy_type just_destroy_type])
            )
          end
          next unless pending.exists?

          raise Exceptions::OperationError, 'Dataset plan has a conflicting pending confirmation'
        end
      end

      def dataset_plan
        @dataset_plan ||= ::DatasetPlan.find_or_create_by!(name: @name)
      end

      def env_dataset_plan(dip)
        ::EnvironmentDatasetPlan.where(
          environment: dip.pool.node.location.environment,
          dataset_plan:
        ).sole
      rescue ::ActiveRecord::RecordNotFound
        raise Exceptions::DatasetPlanNotInEnvironment.new(
          dataset_plan,
          dip.pool.node.location.environment
        )
      rescue ::ActiveRecord::SoleRecordExceeded
        raise Exceptions::OperationError, 'Environment dataset plan is ambiguous'
      end

      private

      def check_source!(dip, confirmation:)
        chain_id = confirmation.transaction_chain_id if confirmation.respond_to?(:transaction_chain_id)
        [dip.dataset, dip].each do |source|
          lock = source.get_current_lock
          own_lock = chain_id && lock && lock.locked_by_type == 'TransactionChain' && lock.locked_by_id == chain_id
          if lock && !own_lock
            raise ::ResourceLocked.new(source, 'Dataset plan source is locked by another chain')
          end

          next if source.confirmed?

          owned_create = chain_id && ::TransactionConfirmation.where(
            done: 0, table_name: source.class.table_name, row_pks: { 'id' => source.id }, confirm_type: :create_type,
            transaction_id: ::Transaction.where(transaction_chain_id: chain_id).select(:id)
          ).exists?
          unless own_lock || owned_create
            raise Exceptions::OperationError, 'Dataset plan source is not confirmed by this chain'
          end
        end
        check_pending_confirmations!([dip.dataset, dip], confirmation:)
      end
    end

    def self.initialize
      plans.each_value(&:dataset_plan)
    end

    def self.register(&)
      Registrator.module_exec(&)
    end

    def self.plans
      Registrator.plans
    end

    def self.confirm
      VpsAdmin::Scheduler.regenerate
    end
  end
end
