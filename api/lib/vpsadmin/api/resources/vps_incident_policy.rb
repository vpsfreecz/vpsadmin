class VpsAdmin::API::Resources::VPS::IncidentPolicy < HaveAPI::Resource
  route '{vps_id}/incident_policies'
  desc 'Read and configure VPS incident policies'

  params(:settings) do
    integer :warning_limit_override, label: 'Warning limit override', nullable: true
    integer :stop_limit_override, label: 'Shutdown limit override', nullable: true
  end

  params(:all) do
    string :key, label: 'Policy key'
    string :label
    text :description, nullable: true
    integer :warning_period_days, label: 'Warning period (days)'
    integer :stop_period_days, label: 'Shutdown period (days)'
    string :settings_category, label: 'Settings category'
    integer :count_7d, label: 'Incidents in 7 days'
    integer :count_30d, label: 'Incidents in 30 days'
    bool :configuration_valid, label: 'Configuration valid'
    integer :warning_limit, label: 'Warning limit', nullable: true
    integer :stop_limit, label: 'Shutdown limit', nullable: true
    string :status, choices: { values: { 'clear' => 'Below limits', 'near_limit' => 'Approaching a limit', 'warning' => 'Warning limit reached', 'stop_threshold' => 'Shutdown limit reached' } }, nullable: true
    string :global_mode, label: 'Global mode', choices: { values: { 'observe' => 'Observation only', 'notify' => 'Warnings only', 'enforce' => 'Automatic shutdown permitted' } }
    string :effective_mode, label: 'Effective mode', choices: { values: { 'observe' => 'Observation only', 'notify' => 'Warnings only', 'enforce' => 'Automatic shutdown permitted' } }, nullable: true
    bool :stop_enforced, label: 'Automatic shutdown permitted', nullable: true
    datetime :last_incident_at, label: 'Last incident', nullable: true
    datetime :last_warning_at, label: 'Last warning queued', nullable: true
    integer :evaluation_report_id, label: 'Last policy evaluation report', nullable: true
    datetime :evaluated_at, label: 'Policy evaluated at', nullable: true
    string :evaluation_state, label: 'Policy evaluation state', choices: { values: { 'none' => 'Not recorded', 'recorded' => 'Recorded', 'error' => 'Failed' } }
    use :settings
  end

  class Index < HaveAPI::Action
    http_method :get
    route ''
    desc 'List incident policies for a VPS'

    output(:object_list) { use :all }

    authorize do |user|
      allow if user.role == :admin
      restrict user_id: user.id
      output blacklist: %i[settings_category warning_limit_override stop_limit_override]
      allow
    end

    def prepare
      @vps = ::Vps.including_deleted.find_by!(with_restricted(id: path_params['vps_id']))
    end

    def exec
      ::VpsIncidentSummary.policy_rows([@vps], language: ::I18n.locale).fetch(@vps.id)
    end
  end

  class Show < HaveAPI::Action
    http_method :get
    route '{key}'
    desc 'Show an incident policy for a VPS'
    output(:object) { use :all }

    authorize do |user|
      allow if user.role == :admin
      restrict user_id: user.id
      output blacklist: %i[settings_category warning_limit_override stop_limit_override]
      allow
    end

    def prepare
      @vps = ::Vps.including_deleted.find_by!(with_restricted(id: path_params['vps_id']))
      error!(VpsAdmin::API::I18n.t('errors.incident_escalation.unknown_policy')) unless ::IncidentEscalation::RULES.has_key?(path_params['key'])
    end

    def exec
      ::VpsIncidentSummary.policy_rows([@vps], language: ::I18n.locale).fetch(@vps.id).find { |row| row[:key] == path_params['key'] }
    end
  end

  class Update < HaveAPI::Action
    include VpsAdmin::API::Lifetimes::ActionHelpers
    include VpsAdmin::API::Maintainable::Check

    http_method :put
    route '{key}'
    desc 'Update VPS incident policy limits'

    input { use :settings }
    output(:object) { use :all }

    authorize do |user|
      allow if user.role == :admin
    end

    def prepare
      @vps = ::Vps.including_deleted.find(path_params['vps_id'])
      error!(VpsAdmin::API::I18n.t('errors.incident_escalation.unknown_policy')) unless ::IncidentEscalation::RULES.has_key?(path_params['key'])
      maintenance_check!(@vps)
      object_state_check!(@vps, @vps.user)
    end

    def exec
      error!(VpsAdmin::API::I18n.t('errors.incident_escalation.limit_required')) if input.empty?
      ::IncidentEscalation.update_policy!(@vps, path_params['key'], input)
      ::VpsIncidentSummary.policy_rows([@vps], language: ::I18n.locale).fetch(@vps.id).find { |row| row[:key] == path_params['key'] }
    rescue ActiveRecord::RecordInvalid => e
      error!(VpsAdmin::API::I18n.t('errors.incident_escalation.unable_to_save_limits'), e.record.errors.to_hash)
    end
  end
end
