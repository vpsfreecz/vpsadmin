module VpsAdmin::API::Resources
  class OomReportRule < HaveAPI::Resource
    LEGACY_WRITE_DISABLED_MESSAGE =
      'OOM report rules have moved to notification event routes'.freeze

    desc 'Inspect deprecated VPS OOM report rules'
    model ::OomReportRule

    params(:common) do
      resource VPS, value_label: :hostname
      string :action, choices: ::OomReportRule.actions.keys.map(&:to_s)
      string :cgroup_pattern, label: 'Cgroup path pattern'
      integer :hit_count, label: 'Hit count'
    end

    params(:all) do
      id :id
      use :common
      string :label
      datetime :created_at
      datetime :updated_at
    end

    class Index < HaveAPI::Actions::Default::Index
      input do
        use :common, include: %i[vps]
      end

      output(:object_list) do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict vpses: { user_id: u.id }
        allow
      end

      def query
        q = self.class.model.joins(:vps).where(with_restricted)
        q = q.where(vps: input[:vps]) if input[:vps]
        q
      end

      def count
        query.count
      end

      def exec
        with_pagination(query).order('id')
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      desc 'Show OOM report rule'

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict vpses: { user_id: u.id }
        allow
      end

      def exec
        self.class.model.joins(:vps).find_by!(with_restricted(id: path_params['oom_report_rule_id']))
      end
    end

    class Create < HaveAPI::Actions::Default::Create
      include VpsAdmin::API::Lifetimes::ActionHelpers

      desc 'Deprecated; configure vps.oom_report event routes instead'

      input do
        use :common

        %i[vps action cgroup_pattern].each do |v|
          patch v, required: true
        end
      end

      output do
        use :all
      end

      authorize do |_u|
        allow
      end

      def exec
        if current_user.role != :admin && input[:vps].user != current_user
          error!('access denied')
        end

        object_state_check!(input[:vps], input[:vps].user)
        error!(::VpsAdmin::API::Resources::OomReportRule::LEGACY_WRITE_DISABLED_MESSAGE)
      end
    end

    class Update < HaveAPI::Actions::Default::Update
      include VpsAdmin::API::Lifetimes::ActionHelpers

      desc 'Deprecated; configure vps.oom_report event routes instead'

      input do
        use :common, include: %i[action cgroup_pattern]
      end

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict vpses: { user_id: u.id }
        allow
      end

      def exec
        rule = self.class.model.joins(:vps).find_by!(with_restricted(id: path_params['oom_report_rule_id']))
        object_state_check!(rule.vps, rule.vps.user)
        error!(::VpsAdmin::API::Resources::OomReportRule::LEGACY_WRITE_DISABLED_MESSAGE)
      end
    end

    class Delete < HaveAPI::Actions::Default::Delete
      include VpsAdmin::API::Lifetimes::ActionHelpers

      desc 'Deprecated; configure vps.oom_report event routes instead'

      authorize do |u|
        allow if u.role == :admin
        restrict vpses: { user_id: u.id }
        allow
      end

      def exec
        rule = self.class.model.joins(:vps).find_by!(with_restricted(id: path_params['oom_report_rule_id']))
        object_state_check!(rule.vps, rule.vps.user)
        error!(::VpsAdmin::API::Resources::OomReportRule::LEGACY_WRITE_DISABLED_MESSAGE)
      end
    end
  end
end
