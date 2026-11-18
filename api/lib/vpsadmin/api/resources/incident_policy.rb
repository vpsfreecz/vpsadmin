module VpsAdmin::API::Resources
  class IncidentPolicy < HaveAPI::Resource
    desc 'Discover incident policies'

    params(:metadata) do
      string :key, label: 'Policy key'
      string :label
      text :description, nullable: true
      integer :warning_period_days, label: 'Warning period (days)'
      integer :stop_period_days, label: 'Shutdown period (days)'
      string :settings_category, label: 'Settings category'
    end

    class Index < HaveAPI::Action
      http_method :get
      route ''
      desc 'List active incident policies'

      output(:object_list) { use :metadata }

      authorize do |user|
        allow if user.role == :admin
        output blacklist: [:settings_category]
        allow
      end

      def exec
        ::IncidentEscalation::RULES.values.map { |rule| ::VpsIncidentSummary.registry_row(rule, language: ::I18n.locale) }
      end
    end

    class Show < HaveAPI::Action
      http_method :get
      route '{key}'
      desc 'Show an active incident policy'

      output(:object) { use :metadata }

      authorize do |user|
        allow if user.role == :admin
        output blacklist: [:settings_category]
        allow
      end

      def exec
        rule = ::IncidentEscalation::RULES[path_params['key']]
        error!(VpsAdmin::API::I18n.t('errors.incident_escalation.unknown_policy')) unless rule
        ::VpsIncidentSummary.registry_row(rule, language: ::I18n.locale)
      end
    end
  end
end
