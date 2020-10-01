module VpsAdmin::API::Resources
  class OomReport < HaveAPI::Resource
    desc 'Out-of-memory kill reports'
    model ::OomReport

    params(:all) do
      id :id
      resource VpsAdmin::API::Resources::VPS, value_label: :hostname
      integer :invoked_by_pid
      string :invoked_by_name
      integer :killed_pid
      string :killed_name
      datetime :created_at
      datetime :reported_at
    end

    params(:filters) do
      resource VpsAdmin::API::Resources::VPS, value_label: :hostname
      resource VpsAdmin::API::Resources::User
      resource VpsAdmin::API::Resources::Node
      resource VpsAdmin::API::Resources::Location
      resource VpsAdmin::API::Resources::Environment
      datetime :since
      datetime :until
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List OOM kill reports'

      input do
        use :filters
      end

      output(:object_list) do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict vpses: {user_id: u.id}
        input blacklist: %i(user)
        allow
      end

      def query
        q = self.class.model.joins(:vps).all.where(with_restricted)

        q = q.where(vps: input[:vps]) if input[:vps]
        q = q.where(vpses: {user_id: input[:user].id}) if input[:user]
        q = q.where(vpses: {node_id: input[:node].id}) if input[:node]

        if input[:location]
          q = q.joins(vpses: :node).where(
            nodes: {location_id: input[:location].id},
          )
        end

        if input[:environment]
          q = q.joins(vpses: {node: :location}).where(
            locations: {environment_id: input[:environment].id},
          )
        end

        if input[:since]
          q = q.where('oom_reports.created_at >= ?', input[:since])
        end

        if input[:until]
          q = q.where('oom_reports.created_at <= ?', input[:until])
        end

        q
      end

      def count
        query.count
      end

      def exec
        query
          .order('oom_reports.created_at DESC, oom_reports.id DESC')
          .offset(input[:offset])
          .limit(input[:limit])
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      desc 'Show OOM kill report'

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict vpses: {user_id: u.id}
        allow
      end

      def prepare
        @oom = ::OomReport.joins(:vps).find_by(with_restricted(id: params[:oom_report_id]))
      end

      def exec
        @oom
      end
    end

    class Usage < HaveAPI::Resource
      desc 'Memory usage'
      model ::OomReportUsage
      route '{oom_report_id}/usages'

      params(:all) do
        id :id
        string :memtype
        integer :usage
        integer :limit
        integer :failcnt
      end

      class Index < HaveAPI::Actions::Default::Index
        desc 'List memory usages'

        output(:object_list) do
          use :all
        end

        authorize do |u|
          allow if u.role == :admin
          restrict vpses: {user_id: u.id}
          allow
        end

        def query
          self.class.model.joins(oom_report: :vps).all.where(with_restricted(
            oom_report_id: params[:oom_report_id],
          ))
        end

        def count
          query.count
        end

        def exec
          query.offset(input[:offset]).limit(input[:limit])
        end
      end

      class Show < HaveAPI::Actions::Default::Show
        desc 'Show memory usage'

        output(:object_list) do
          use :all
        end

        authorize do |u|
          allow if u.role == :admin
          restrict vpses: {user_id: u.id}
          allow
        end

        def prepare
          @usage = self.class.model.joins(oom_report: :vps).find_by(with_restricted(
            oom_report_id: params[:oom_report_id],
            id: params[:usage_id],
          ))
        end

        def exec
          @usage
        end
      end
    end

    class Stat < HaveAPI::Resource
      desc 'Memory stats'
      model ::OomReportStat
      route '{oom_report_id}/stats'

      params(:all) do
        id :id
        string :parameter
        integer :value
      end

      class Index < HaveAPI::Actions::Default::Index
        desc 'List memory stats'

        output(:object_list) do
          use :all
        end

        authorize do |u|
          allow if u.role == :admin
          restrict vpses: {user_id: u.id}
          allow
        end

        def query
          self.class.model.joins(oom_report: :vps).all.where(with_restricted(
            oom_report_id: params[:oom_report_id],
          ))
        end

        def count
          query.count
        end

        def exec
          query.offset(input[:offset]).limit(input[:limit])
        end
      end

      class Show < HaveAPI::Actions::Default::Show
        desc 'Show memory stat'

        output(:object_list) do
          use :all
        end

        authorize do |u|
          allow if u.role == :admin
          restrict vpses: {user_id: u.id}
          allow
        end

        def prepare
          @stat = self.class.model.joins(oom_report: :vps).find_by(with_restricted(
            oom_report_id: params[:oom_report_id],
            id: params[:stat_id],
          ))
        end

        def exec
          @stat
        end
      end
    end

    class Task < HaveAPI::Resource
      desc 'Task list'
      model ::OomReportTask
      route '{oom_report_id}/tasks'

      params(:all) do
        id :id
        string :name
        integer :host_pid
        integer :vps_pid
        integer :vps_uid
        integer :tgid
        integer :total_vm
        integer :rss
        integer :pgtables_bytes
        integer :swapents
        integer :oom_score_adj
      end

      class Index < HaveAPI::Actions::Default::Index
        desc 'List tasks'

        output(:object_list) do
          use :all
        end

        authorize do |u|
          allow if u.role == :admin
          restrict vpses: {user_id: u.id}
          allow
        end

        def query
          self.class.model.joins(oom_report: :vps).all.where(with_restricted(
            oom_report_id: params[:oom_report_id],
          ))
        end

        def count
          query.count
        end

        def exec
          query.offset(input[:offset]).limit(input[:limit])
        end
      end

      class Show < HaveAPI::Actions::Default::Show
        desc 'Show task'

        output(:object_list) do
          use :all
        end

        authorize do |u|
          allow if u.role == :admin
          restrict vpses: {user_id: u.id}
          allow
        end

        def prepare
          @task = self.class.model.joins(oom_report: :vps).find_by(with_restricted(
            oom_report_id: params[:oom_report_id],
            id: params[:task_id],
          ))
        end

        def exec
          @task
        end
      end
    end
  end
end
