module VpsAdmin::API::Resources
  class MigrationPlan < HaveAPI::Resource
    desc 'View migration plans'
    model ::MigrationPlan
    
    params(:all) do
      id :id
      string :state, choices: ::MigrationPlan.states.keys
      bool :stop_on_error
      bool :send_mail
      resource User, value_label: :login
      integer :concurrency
      string :reason
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

    class VpsMigration < HaveAPI::Resource
      desc 'VPS migrations'
      route ':migration_plan_id/vps_migrations'
      model ::VpsMigration

      params(:all) do
        resource VpsAdmin::API::Resources::VPS, value_label: :hostname
        string :state, choices: ::VpsMigration.states.keys
        resource VpsAdmin::API::Resources::TransactionChain
        resource VpsAdmin::API::Resources::Node, name: :src_node, value_label: :domain_name
        resource VpsAdmin::API::Resources::Node, name: :dst_node, value_label: :domain_name
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
    end
  end
end
