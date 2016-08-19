module VpsAdmin::API
  module DatasetPlans
    # Register and store of properties.
    module Registrator
      def self.plan(name, label: nil, desc: nil, &block)
        @plans ||= {}
        @plans[name] = Plan.new(name, label, desc, &block)
      end

      def self.plans
        @plans
      end
    end

    class Executor
      def initialize(plan, confirmation)
        @env_plan = plan
        @confirm = confirmation
      end

      def add_group_snapshot(dip, min, hour, day, month, dow)
        action = ::DatasetAction.joins(:dataset_plan).where(
            pool_id: dip.pool_id,
            action: ::DatasetAction.actions[:group_snapshot],
            dataset_plan: @env_plan.dataset_plan
        ).take

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
              minute: min,
              hour: hour,
              day_of_month: day,
              month: month,
              day_of_week: dow
          )

          confirm(:just_create, task)
        end

        grp = ::GroupSnapshot.create!(
            dataset_in_pool: dip,
            dataset_action: action
        )

        confirm(:just_create, grp)
      end

      def del_group_snapshot(dip, *_)
        gsnap = ::GroupSnapshot.joins(:dataset_action).where(
            dataset_actions: {
                pool_id: dip.pool_id,
                action: ::DatasetAction.actions[:group_snapshot],
                dataset_plan_id: @env_plan.dataset_plan_id
            },
            dataset_in_pool: dip
        ).take!
        
        if confirm?
          confirm(:just_destroy, gsnap)
        else
          gsnap.destroy!
        end
      end

      def add_backup(dip, min, hour, day, month, dow)
        plan = ::DatasetInPoolPlan.find_by!(
            environment_dataset_plan: @env_plan,
            dataset_in_pool: dip
        )

        action = ::DatasetAction.create!(
            src_dataset_in_pool: dip,
            dst_dataset_in_pool: dip.dataset.dataset_in_pools.joins(:pool).where(pools: {role: ::Pool.roles[:backup]}).take!,
            dataset_in_pool_plan: plan,
            action: ::DatasetAction.actions[:backup],
        )

        confirm(:just_create, action)

        task = ::RepeatableTask.create!(
            class_name: action.class.name,
            table_name: action.class.table_name,
            row_id: action.id,
            minute: min,
            hour: hour,
            day_of_month: day,
            month: month,
            day_of_week: dow
        )

        confirm(:just_create, task)
      end

      def del_backup(dip, *_)
        plan = ::DatasetInPoolPlan.find_by!(
            environment_dataset_plan: @env_plan,
            dataset_in_pool: dip
        )

        ::DatasetAction.where(
            dataset_in_pool_plan: plan,
            action: ::DatasetAction.actions[:backup]
        ).each do |a|
          task = ::RepeatableTask.find_for!(a)

          if confirm?
            confirm(:just_destroy, task)
            confirm(:just_destroy, a)

          else
            task.destroy!
            a.destroy!
          end
        end
      end

      def confirm(type, *args)
        return unless @confirm
        @confirm.send(type, *args)
      end

      def confirm?
        @confirm ? true : false
      end
    end

    # Represents a single dataset plan.
    class Plan
      class BlockEnv
        def initialize(direction, plan, confirmation = nil)
          @direction = direction
          @plan = plan
          @confirmation = confirmation
        end

        def group_snapshot(dip, *args)
          task(:group_snapshot, dip, *args)
        end

        def backup(dip, *args)
          task(:backup, dip, *args)
        end

        protected
        def task(name, *args)
          @exec ||= Executor.new(@plan, @confirmation)
          @exec.method("#{@direction}_#{name}").call(*args)
        end
      end

      attr_reader :name, :label, :desc

      def initialize(name, label, desc, &block)
        @name = name
        @label = label
        @desc = desc
        @block = block
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

        ::DatasetInPoolPlan.transaction do
          plan = ::DatasetInPoolPlan.create!(
              environment_dataset_plan: env_dataset_plan(dip),
              dataset_in_pool: dip
          )

          confirmation.just_create(plan) if confirmation

          BlockEnv.new(:add, env_dataset_plan(dip), confirmation).instance_exec(dip, &@block)
        end

        plan
      end

      def unregister(dip, confirmation: nil)
        ::DatasetInPoolPlan.transaction do
          BlockEnv.new(:del, env_dataset_plan(dip), confirmation).instance_exec(dip, &@block)

          plan = ::DatasetInPoolPlan.find_by!(
              environment_dataset_plan: env_dataset_plan(dip),
              dataset_in_pool: dip
          )
          
          if confirmation
            confirmation.just_destroy(plan)
          else
            plan.destroy!
          end
        end
      end

      def dataset_plan
        @dataset_plan ||= ::DatasetPlan.find_or_create_by!(name: @name)
      end

      def env_dataset_plan(dip)
        @env_dataset_plan ||= ::EnvironmentDatasetPlan.find_by!(
            environment: dip.pool.node.location.environment,
            dataset_plan: dataset_plan
        )

      rescue ::ActiveRecord::RecordNotFound
        raise Exceptions::DatasetPlanNotInEnvironment.new(
            dataset_plan,
            dip.pool.node.environment
        )
      end
    end

    def self.initialize
      plans.each_value { |p| p.dataset_plan }
    end

    def self.register(&block)
      Registrator.module_exec(&block)
    end

    def self.plans
      Registrator.plans
    end

    def self.confirm
      VpsAdmin::Scheduler.regenerate
    end
  end
end
