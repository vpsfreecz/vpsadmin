module VpsAdmin::API::Resources
  class IncidentReport < HaveAPI::Resource
    model ::IncidentReport
    desc 'Manage incident reports'

    params(:id) do
      integer :id, label: 'ID'
    end

    params(:common) do
      resource User, value_label: :login
      resource VPS, value_label: :hostname
      resource IpAddressAssignment, value_label: :ip_addr, label: 'IP address assignment'
      resource User, name: :filed_by, value_label: :login
      resource Mailbox, nullable: true
      string :subject
      text :text
      string :codename
      integer :cpu_limit, label: 'CPU limit'
      string :vps_action, label: 'VPS action', choices: ::IncidentReport.vps_actions.keys.map(&:to_s),
                          default: 'none', fill: true
    end

    params(:all) do
      use :id
      use :common
      integer :raw_user_id
      integer :raw_vps_id
      datetime :detected_at
      datetime :created_at
      datetime :reported_at
    end

    params(:notice) do
      string :notice_policy_key, nullable: true, label: 'Notice policy key'
      string :notice_policy_label, nullable: true, label: 'Notice policy label'
      string :notice_kind, nullable: true, choices: { values: { 'stop_completed' => 'Automatic stop confirmed', 'warning' => 'Warning about repeated incidents' } }, label: 'Escalation notice kind',
                           desc: 'Recorded escalation warning decision or confirmed stop outcome; not proof of mail delivery.'
      integer :trigger_incident_report_id, nullable: true, label: 'Source incident report ID', desc: 'Authorized original source report for an escalation notice.'
      string :notice_mail_state, nullable: true, choices: { values: { 'failed' => 'Sending failed', 'pending' => 'Not yet queued', 'queued' => 'Queued for sending', 'sent' => 'Accepted by mail server', 'suppressed' => 'Sending suppressed', 'uncertain' => 'Sending outcome uncertain' } }, label: 'Escalation mail state',
                                 desc: 'State of the escalation email. Sent means accepted by the mail server; inbox delivery is not confirmed.'
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List incident reports'

      input do
        use :common, include: %i[user vps ip_address_assignment filed_by mailbox codename]
        string :ip_addr, label: 'IP address'
        string :policy_key, label: 'Policy key',
                            desc: 'Filter by saved policy membership, including removed policies.'
      end

      output(:object_list) do
        use :all
        use :notice
      end

      authorize do |u|
        allow if u.role == :admin
        restrict user_id: u.id
        output blacklist: %i[user mailbox]
        allow
      end

      def query
        q = ::IncidentReport.visible_in_owner_epoch(current_user).where(with_restricted)

        %i[user vps ip_address_assignment filed_by mailbox codename].each do |v|
          q = q.where(v => input[v]) if input.has_key?(v)
        end

        if input[:policy_key]
          q = q.where(<<~SQL.squish, input[:policy_key], input[:policy_key])
            EXISTS (SELECT 1 FROM incident_policy_evaluations e WHERE e.incident_report_id = incident_reports.id
              AND e.policy_key = ? AND e.matched = TRUE) OR EXISTS (
                SELECT 1 FROM vps_incident_actions a WHERE a.notice_incident_report_id = incident_reports.id AND a.policy_key = ?)
          SQL
        end

        if input[:ip_addr]
          q = q.joins(:ip_address_assignment).where(
            ip_address_assignments: { ip_addr: input[:ip_addr] }
          )

          if current_user.role != :admin
            q = q.where(
              ip_address_assignments: { user_id: current_user.id }
            )
          end
        end

        q
      end

      def count
        query.count
      end

      def exec
        with_desc_pagination(with_includes(query).includes(notice_action: :incident_report).order(detected_at: :desc))
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      desc 'Show incident report'

      output do
        use :all
        use :notice
      end

      authorize do |u|
        allow if u.role == :admin
        restrict user_id: u.id
        output blacklist: %i[user mailbox]
        allow
      end

      def prepare
        scope = ::IncidentReport.visible_in_owner_epoch(current_user)

        @incident = with_includes(scope).find_by!(with_restricted(
                                                    id: path_params['incident_report_id']
                                                  ))
      end

      def exec
        @incident
      end
    end

    class Create < HaveAPI::Actions::Default::Create
      desc 'Create incident report'
      blocking true

      input do
        use :all, include: %i[vps ip_address_assignment subject text codename detected_at cpu_limit vps_action]

        %i[vps subject text].each do |v|
          patch v, required: true
        end
      end

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        ::IncidentEscalation.serialized(input[:vps], requires_new: true) do
          incident = ::IncidentReport.create!(
            user: input[:vps].user,
            vps: input[:vps],
            ip_address_assignment: input[:ip_address_assignment],
            filed_by: current_user,
            subject: input[:subject],
            text: input[:text],
            codename: input[:codename],
            detected_at: input[:detected_at] || Time.now,
            cpu_limit: input[:cpu_limit],
            vps_action: input[:vps_action]
          )
          @chain, = TransactionChains::IncidentReport::New.fire2(
            args: [incident]
          )
          incident
        end
      end

      def state_id
        @chain&.id
      end
    end
  end
end

class VpsAdmin::API::Resources::IncidentReport::PolicyEvaluation < HaveAPI::Resource
  route '{incident_report_id}/policy_evaluations'
  desc 'Read saved incident policy evaluations'

  class Index < HaveAPI::Action
    http_method :get
    route ''
    desc 'List saved policy outcomes for an incident report'

    output(:object_list) do
      bool :matched, nullable: true, label: 'Matched policy'
      integer :warning_period_days, label: 'Warning period in days'
      integer :stop_period_days, label: 'Shutdown period in days'
      string :policy_key, label: 'Policy key'
      string :label
      datetime :evaluated_at, label: 'Policy evaluated at'
      integer :count_7d, label: 'Incidents in 7 days', nullable: true
      integer :count_30d, label: 'Incidents in 30 days', nullable: true
      integer :warning_limit, label: 'Warning limit', nullable: true
      integer :stop_limit, label: 'Shutdown limit', nullable: true
      string :effective_mode, label: 'Effective mode', choices: { values: { 'observe' => 'Observation only', 'notify' => 'Warnings only', 'enforce' => 'Automatic shutdown permitted' } }, nullable: true
      bool :stop_enforced, label: 'Automatic shutdown permitted', nullable: true
      string :decision, label: 'Decision', choices: { values: { 'none' => 'No action', 'warning' => 'Warning', 'stop' => 'Shutdown' } }
      string :state, choices: { values: { 'recorded' => 'recorded', 'skipped' => 'skipped', 'error' => 'error', 'audit_only' => 'audit only' } }
      string :error_stage, label: 'Error stage', nullable: true
      string :error_class, label: 'Error class', nullable: true
    end

    authorize do |user|
      allow if user.role == :admin
      restrict user_id: user.id
      output blacklist: %i[error_stage error_class]
      allow
    end

    def prepare
      @incident = ::IncidentReport.visible_in_owner_epoch(current_user).find_by!(with_restricted(id: path_params['incident_report_id']))
    end

    def exec
      scope = @incident.incident_policy_evaluations
      scope = scope.member_visible if current_user.role != :admin
      scope.order(:policy_key).map do |evaluation|
        saved = evaluation.snapshot
        effective = saved['effective'] || {}
        context = saved['context'] || {}
        {
          matched: evaluation.matched, warning_period_days: 7, stop_period_days: 30,
          policy_key: evaluation.policy_key, label: evaluation.label(::I18n.locale), evaluated_at: evaluation.evaluated_at,
          count_7d: context['count_7d'], count_30d: context['count_30d'], warning_limit: effective['warning_limit'],
          stop_limit: effective['stop_limit'], effective_mode: effective['mode'],
          stop_enforced: effective.empty? ? nil : effective['mode'] == 'enforce' && !effective['stop_exempt'] && !effective['suppress_actions'],
          decision: saved.fetch('decision'), state: evaluation.state,
          error_stage: saved['error_stage'], error_class: saved['error_class']
        }
      end
    end
  end
end
