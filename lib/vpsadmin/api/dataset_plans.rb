module VpsAdmin::API
  module DatasetPlans
    # Register and store of properties.
    module Registrator
      def self.plan(name, label: nil, &block)
        @plans ||= {}
        @plans[name] = Plan.new(name, label, &block)
      end

      def self.plans
        @plans
      end
    end

    class Executor
      def initialize(plan)
        @plan = plan
      end

      def add_group_snapshot(dip, min, hour, day, month, dow)
        action = ::DatasetAction.joins(:dataset_plan).where(
            pool_id: dip.pool_id,
            action: ::DatasetAction.actions[:group_snapshot],
            dataset_plan: @plan
        ).take

        unless action
          action = ::DatasetAction.create!(
              pool_id: dip.pool_id,
              action: ::DatasetAction.actions[:group_snapshot],
              dataset_plan: @plan
          )

          ::RepeatableTask.create!(
              class_name: action.class.name,
              table_name: action.class.table_name,
              row_id: action.id,
              minute: min,
              hour: hour,
              day_of_month: day,
              month: month,
              day_of_week: dow
          )
        end

        action.group_snapshots << ::GroupSnapshot.new(
            dataset_in_pool: dip
        )
      end

      def del_group_snapshot(dip, *_)
        ::GroupSnapshot.joins(:dataset_action).where(
            dataset_actions: {
                pool_id: dip.pool_id,
                action: ::DatasetAction.actions[:group_snapshot],
                dataset_plan_id: @plan.id
            },
            dataset_in_pool: dip
        ).take!.destroy!
      end

      def add_backup(dip, min, hour, day, month, dow)
        plan = ::DatasetInPoolPlan.find_by!(
            dataset_plan: @plan,
            dataset_in_pool: dip
        )

        action = ::DatasetAction.create!(
            src_dataset_in_pool: dip,
            dst_dataset_in_pool: dip.dataset.dataset_in_pools.joins(:pool).where(pools: {role: ::Pool.roles[:backup]}).take!,
            dataset_in_pool_plan: plan,
            action: ::DatasetAction.actions[:backup],
        )

        ::RepeatableTask.create!(
            class_name: action.class.name,
            table_name: action.class.table_name,
            row_id: action.id,
            minute: min,
            hour: hour,
            day_of_month: day,
            month: month,
            day_of_week: dow
        )
      end

      def del_backup(dip, *_)
        plan = ::DatasetInPoolPlan.find_by!(
            dataset_plan: @plan,
            dataset_in_pool: dip
        )

        ::DatasetAction.where(
            dataset_in_pool_plan: plan,
            action: ::DatasetAction.actions[:backup]
        ).each do |a|
          ::RepeatableTask.find_for!(a).destroy!
          a.destroy!
        end
      end
    end

    # Represents a single dataset plan.
    class Plan
      class BlockEnv
        def initialize(direction, plan)
          @direction = direction
          @plan = plan
        end

        def group_snapshot(dip, *args)
          task(:group_snapshot, dip, *args)
        end

        def backup(dip, *args)
          task(:backup, dip, *args)
        end

        protected
        def task(name, *args)
          @exec ||= Executor.new(@plan)
          @exec.method("#{@direction}_#{name}").call(*args)
        end
      end

      attr_reader :name, :label

      def initialize(name, label, &block)
        @name = name
        @label = label
        @block = block
      end

      def label(l = nil)
        if l
          @label = l
        else
          @label
        end
      end

      def register(dip)
        plan = nil

        ::DatasetInPoolPlan.transaction do
          plan = ::DatasetInPoolPlan.create!(
              environment_dataset_plan: env_dataset_plan(dip),
              dataset_in_pool: dip
          )

          BlockEnv.new(:add, env_dataset_plan(dip)).instance_exec(dip, &@block)
        end

        plan
      end

      def unregister(dip)
        ::DatasetInPoolPlan.transaction do
          BlockEnv.new(:del, env_dataset_plan(dip)).instance_exec(dip, &@block)

          ::DatasetInPoolPlan.find_by!(
              environment_dataset_plan: env_dataset_plan(dip),
              dataset_in_pool: dip
          ).destroy!
        end
      end

      def dataset_plan
        @dataset_plan ||= ::DatasetPlan.find_or_create_by!(name: @name)
      end

      def env_dataset_plan(dip)
        @env_dataset_plan ||= ::EnvironmentDatasetPlan.find_by!(
            environment: dip.pool.node.environment,
            dataset_plan: dataset_plan
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
