module VpsAdmin::API::Resources
  class OomReportRule < HaveAPI::Resource
    desc 'Manage VPS OOM report rules'
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
        self.class.model.joins(:vps).find_by!(with_restricted(id: params[:oom_report_rule_id]))
      end
    end

    class Create < HaveAPI::Actions::Default::Create
      desc 'Create a new OOM report rule'

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

        if input[:vps].oom_report_rules.count > 100
          error!('rule limit reached, refusing to add another one')
        end

        self.class.model.create!(input)
      rescue ActiveRecord::RecordInvalid => e
        error!('create failed', e.record.errors.to_hash)
      end
    end

    class Update < HaveAPI::Actions::Default::Update
      desc 'Update OOM report rule'

      input do
        use :common
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
        self.class.model.joins(:vps).find_by!(with_restricted(id: params[:oom_report_rule_id])).update!(input)
      end
    end

    class Delete < HaveAPI::Actions::Default::Delete
      desc 'Delete OOM report rule'

      authorize do |u|
        allow if u.role == :admin
        restrict vpses: { user_id: u.id }
        allow
      end

      def exec
        self.class.model.joins(:vps).find_by!(with_restricted(id: params[:oom_report_rule_id])).destroy!
        ok!
      end
    end
  end
end
