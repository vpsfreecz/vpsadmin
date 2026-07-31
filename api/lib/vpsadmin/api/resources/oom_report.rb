require_relative '../events/report_mute_route'

module VpsAdmin::API::Resources
  class OomReport < HaveAPI::Resource
    desc 'Out-of-memory kill reports'
    model ::OomReport

    params(:all) do
      id :id
      resource VpsAdmin::API::Resources::VPS, value_label: :hostname
      string :cgroup
      integer :invoked_by_pid
      string :invoked_by_name
      integer :killed_pid
      string :killed_name
      integer :count
      datetime :created_at
    end

    params(:filters) do
      resource VpsAdmin::API::Resources::VPS, value_label: :hostname
      resource VpsAdmin::API::Resources::User
      resource VpsAdmin::API::Resources::Node
      resource VpsAdmin::API::Resources::Location
      resource VpsAdmin::API::Resources::Environment
      string :cgroup
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
        restrict vpses: { user_id: u.id }
        input blacklist: %i[user]
        allow
      end

      def query
        q = self.class.model.joins(:vps).all.where(with_restricted)

        q = q.where(vps: input[:vps]) if input[:vps]
        q = q.where(vpses: { user_id: input[:user].id }) if input[:user]
        q = q.where(vpses: { node_id: input[:node].id }) if input[:node]

        if input[:location]
          q = q.joins(vps: :node).where(
            nodes: { location_id: input[:location].id }
          )
        end

        if input[:environment]
          q = q.joins(vps: { node: :location }).where(
            locations: { environment_id: input[:environment].id }
          )
        end

        q = q.where('oom_reports.cgroup = ?', input[:cgroup]) if input[:cgroup]

        q = q.where('oom_reports.created_at >= ?', input[:since]) if input[:since]

        q = q.where('oom_reports.created_at <= ?', input[:until]) if input[:until]

        q
      end

      def count
        query.count
      end

      def exec
        with_desc_pagination(query).order('oom_reports.created_at DESC')
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      desc 'Show OOM kill report'

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict vpses: { user_id: u.id }
        allow
      end

      def prepare
        @oom = ::OomReport.joins(:vps).find_by(with_restricted(id: path_params['oom_report_id']))
      end

      def exec
        @oom
      end
    end

    class MuteSimilar < HaveAPI::Action
      desc 'Create a mute route matching values from this OOM report'
      route '{%{resource}_id}/mute_similar'
      http_method :post

      input do
        resource VpsAdmin::API::Resources::User,
                 name: :route_owner,
                 value_label: :login,
                 nullable: true
        bool :match_vps, default: false, fill: true
        bool :match_cgroup, default: false, fill: true
        bool :match_invoked_by_name, default: false, fill: true
        bool :match_killed_name, default: false, fill: true
        datetime :expires_at,
                 label: 'Expires at',
                 desc: 'Optional date and time after which this route stops matching events',
                 desc_key: 'vpsadmin.resources.event_route.attributes.expires_at.description',
                 nullable: true
      end

      output namespace: :event_route do
        id :id
        integer :user_id
        integer :notification_receiver_id, nullable: true
        string :label, nullable: true
        integer :position
        bool :enabled
        string :event_type, nullable: true
        string :subject_scope
        bool :grouping_enabled
        bool :continue
        bool :single_use
        datetime :spent_at, nullable: true
        datetime :expires_at,
                 label: 'Expires at',
                 desc: 'Optional date and time after which this route stops matching events',
                 desc_key: 'vpsadmin.resources.event_route.attributes.expires_at.description',
                 nullable: true
        string :matcher_summary
        integer :matcher_count
        string :display_label
        datetime :created_at
        datetime :updated_at
      end

      authorize do |u|
        allow if u.role == :admin
        restrict vpses: { user_id: u.id }
        allow
      end

      def prepare
        @oom = ::OomReport.joins(:vps).find_by!(with_restricted(
                                                  id: path_params['oom_report_id']
                                                ))
      end

      def exec
        VpsAdmin::API::Events::ReportMuteRoute.new(
          current_user:,
          source_user: @oom.vps.user,
          owner: input[:route_owner],
          event_type: 'vps.oom_report',
          label: "Mute OOM reports like ##{@oom.id}",
          matchers: selected_matchers,
          expires_at: input[:expires_at]
        ).create!
      rescue VpsAdmin::API::Events::ReportMuteRoute::Error => e
        error!(e.message)
      rescue ActiveRecord::RecordInvalid => e
        error!('create failed', e.record.errors.to_hash)
      end

      protected

      def selected_matchers
        {
          match_vps: [:vps_id, @oom.vps_id],
          match_cgroup: [:cgroup, @oom.cgroup],
          match_invoked_by_name: [:invoked_by_name, @oom.invoked_by_name],
          match_killed_name: [:killed_name, @oom.killed_name]
        }.filter_map do |input_name, (field, value)|
          { field:, value: } if input[input_name]
        end
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
          restrict vpses: { user_id: u.id }
          allow
        end

        def query
          self.class.model.joins(oom_report: :vps).all.where(with_restricted(
                                                               oom_report_id: path_params['oom_report_id']
                                                             ))
        end

        def count
          query.count
        end

        def exec
          with_pagination(query)
        end
      end

      class Show < HaveAPI::Actions::Default::Show
        desc 'Show memory usage'

        output do
          use :all
        end

        authorize do |u|
          allow if u.role == :admin
          restrict vpses: { user_id: u.id }
          allow
        end

        def prepare
          @usage = self.class.model.joins(oom_report: :vps).find_by(with_restricted(
                                                                      oom_report_id: path_params['oom_report_id'],
                                                                      id: path_params['usage_id']
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
          restrict vpses: { user_id: u.id }
          allow
        end

        def query
          self.class.model.joins(oom_report: :vps).all.where(with_restricted(
                                                               oom_report_id: path_params['oom_report_id']
                                                             ))
        end

        def count
          query.count
        end

        def exec
          with_pagination(query)
        end
      end

      class Show < HaveAPI::Actions::Default::Show
        desc 'Show memory stat'

        output do
          use :all
        end

        authorize do |u|
          allow if u.role == :admin
          restrict vpses: { user_id: u.id }
          allow
        end

        def prepare
          @stat = self.class.model.joins(oom_report: :vps).find_by(with_restricted(
                                                                     oom_report_id: path_params['oom_report_id'],
                                                                     id: path_params['stat_id']
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
        integer :rss_anon
        integer :rss_file
        integer :rss_shmem
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
          restrict vpses: { user_id: u.id }
          allow
        end

        def query
          self.class.model.joins(oom_report: :vps).all.where(with_restricted(
                                                               oom_report_id: path_params['oom_report_id']
                                                             ))
        end

        def count
          query.count
        end

        def exec
          with_pagination(query)
        end
      end

      class Show < HaveAPI::Actions::Default::Show
        desc 'Show task'

        output do
          use :all
        end

        authorize do |u|
          allow if u.role == :admin
          restrict vpses: { user_id: u.id }
          allow
        end

        def prepare
          @task = self.class.model.joins(oom_report: :vps).find_by(with_restricted(
                                                                     oom_report_id: path_params['oom_report_id'],
                                                                     id: path_params['task_id']
                                                                   ))
        end

        def exec
          @task
        end
      end
    end
  end
end
