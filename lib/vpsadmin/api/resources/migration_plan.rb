module VpsAdmin::API::Resources
  class MigrationPlan < HaveAPI::Resource
    desc 'View migration plans'
    model ::MigrationPlan
   
    params(:editable) do
      bool :stop_on_error, default: true, fill: true
      bool :send_mail, default: true, fill: true
      integer :concurrency, default: 10, fill: true
      string :reason
    end

    params(:all) do
      id :id
      string :state, choices: ::MigrationPlan.states.keys
      use :editable
      resource User, value_label: :login
      datetime :created_at
      datetime :finished_at
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List migration plans'

      input do
        string :state, choices: ::MigrationPlan.states.keys
        resource User
      end

      output(:object_list) do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def query
        q = with_includes
        q = q.where(state: ::MigrationPlan.states[input[:state]]) if input[:state]
        q = q.where(user: input[:user]) if input[:user]
        q
      end

      def count
        query.count
      end

      def exec
        query.offset(input[:offset]).limit(input[:limit])
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      desc 'Show a migration plan'

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def prepare
        @plan = ::MigrationPlan.find(params[:migration_plan_id])
      end

      def exec
        @plan
      end
    end

    class Create < HaveAPI::Actions::Default::Create
      desc 'Create a custom migration plan'

      input do
        use :editable
      end

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        plan = ::MigrationPlan.new(input)
        plan.user = current_user
        plan.save!
        plan

      rescue ActiveRecord::RecordInvalid => e
        error('create failed', e.record.errors.to_hash)
      end
    end

    class Start < HaveAPI::Action
      desc 'Begin execution of a migration plan'
      http_method :post
      route ':%{resource}_id/start'
      
      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        plan = ::MigrationPlan.find(params[:migration_plan_id])

        if plan.state != 'staged'
          error('This migration plan has already been started')
        end

        plan.start!
        plan
      end
    end

    class Cancel < HaveAPI::Action
      desc 'Cancel execution of a migration plan'
      http_method :post
      route ':%{resource}_id/cancel'
      
      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        plan = ::MigrationPlan.find(params[:migration_plan_id])

        if plan.state != 'running'
          error('This migration plan is not running')
        end

        plan.cancel!
        plan
      end
    end

    class Delete < HaveAPI::Actions::Default::Delete
      desc 'Delete staged migration plan'

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        plan = ::MigrationPlan.find(params[:migration_plan_id])

        if plan.state != 'staged'
          error('This migration plan is not in the staging phase anymore')
        end

        plan.destroy
        ok
      end
    end

    class VpsMigration < HaveAPI::Resource
      desc 'VPS migrations'
      route ':migration_plan_id/vps_migrations'
      model ::VpsMigration

      params(:editable) do
        resource VpsAdmin::API::Resources::VPS, value_label: :hostname
        resource VpsAdmin::API::Resources::Node, name: :dst_node, value_label: :domain_name
        bool :outage_window, default: true, fill: true
      end

      params(:all) do
        id :id
        string :state, choices: ::VpsMigration.states.keys
        resource VpsAdmin::API::Resources::TransactionChain
        resource VpsAdmin::API::Resources::Node, name: :src_node, value_label: :domain_name
        use :editable
        datetime :created_at
        datetime :started_at
        datetime :finished_at
      end

      class Index < HaveAPI::Actions::Default::Index
        desc 'List scheduled VPS migrations'

        input do
          string :state, choices: ::VpsMigration.states.keys
          resource VpsAdmin::API::Resources::Node, name: :src_node
          resource VpsAdmin::API::Resources::Node, name: :dst_node
        end

        output(:object_list) do
          use :all
        end

        authorize do |u|
          allow if u.role == :admin
        end

        def query
          q = with_includes.where(
              migration_plan_id: params[:migration_plan_id],
          )
          q = q.where(state: ::VpsMigration.states[input[:state]]) if input[:state]
          q = q.where(src_node: input[:src_node]) if input[:src_node]
          q = q.where(dst_node: input[:dst_node]) if input[:dst_node]
          q
        end

        def count
          query.count
        end

        def exec
          query.offset(input[:offset]).limit(input[:limit])
        end
      end

      class Show < HaveAPI::Actions::Default::Show
        desc 'Show a migration plan'

        output do
          use :all
        end

        authorize do |u|
          allow if u.role == :admin
        end

        def prepare
          @m = ::VpsMigrationPlan.find_by!(
              migration_plan_id: params[:migration_plan_id],
              id: params[:vps_migration_id],
          )
        end

        def exec
          @m
        end
      end

      class Create < HaveAPI::Actions::Default::Create
        desc 'Schedule VPS migration'

        input do
          use :editable
          patch :vps, required: true
          patch :dst_node, required: true
        end

        output do
          use :all
        end

        authorize do |u|
          allow if u.role == :admin
        end

        def exec
          plan = ::MigrationPlan.find(params[:migration_plan_id])

          if plan.state != 'staged'
            error('This migration plans has already been started.')
          end

          plan.vps_migrations.create!(
              vps: input[:vps],
              outage_window: input[:outage_window],
              src_node: input[:vps].node,
              dst_node: input[:dst_node],
          )

        rescue ActiveRecord::RecordInvalid => e
          error('create failed', e.record.errors.to_hash)
        end
      end
    end
  end
end
