# frozen_string_literal: true

require_relative 'notification_templates'

module VpsAdmin::API
  module MailTemplates
    DEFAULT_FROM = 'noreply@vpsadmin.invalid'
    LANGUAGE_LABELS = {
      'en' => 'English',
      'cs' => 'Česky'
    }.freeze
    CONCRETE_DEFAULTS = {
      expiration_user_active: :expiration_warning,
      expiration_vps_active: :expiration_warning,

      request_create_admin: :request_action_role,
      request_create_user: :request_action_role,
      request_update_admin: :request_action_role,
      request_update_user: :request_action_role,
      request_resolve_admin: :request_action_role,
      request_resolve_user: :request_action_role,

      outage_report_generic: :outage_report_role,
      outage_report_user: :outage_report_role,

      alert_admin_monthly_traffic_closed: :alert_role_event_state,
      alert_admin_monthly_traffic_confirmed: :alert_role_event_state,
      alert_admin_unpaid_cpu_closed: :alert_role_event_state,
      alert_admin_unpaid_cpu_confirmed: :alert_role_event_state,
      alert_admin_unpaid_data_flow_closed: :alert_role_event_state,
      alert_admin_unpaid_data_flow_confirmed: :alert_role_event_state,
      alert_user_diskspace_closed_hypervisor: :alert_role_diskspace_state_pool,
      alert_user_diskspace_closed_primary: :alert_role_diskspace_state_pool,
      alert_user_diskspace_confirmed_hypervisor: :alert_role_diskspace_state_pool,
      alert_user_diskspace_confirmed_primary: :alert_role_diskspace_state_pool,
      alert_user_outgoing_data_flow_closed: :alert_role_event_state,
      alert_user_outgoing_data_flow_confirmed: :alert_role_event_state,
      alert_user_paid_cpu_closed: :alert_role_event_state,
      alert_user_paid_cpu_confirmed: :alert_role_event_state,
      alert_user_vps_in_rescue: :alert_user_vps_in_rescue,
      alert_user_zombie_processes_closed: :alert_user_zombie_processes_state,
      alert_user_zombie_processes_confirmed: :alert_user_zombie_processes_state,
      alert_user_zombie_processes_restart: :alert_user_zombie_processes_restart,
      alert_vps_dataset_over_quota: :alert_vps_dataset_over_quota
    }.freeze

    def self.install_defaults!(paths: default_template_paths)
      result = {
        templates_created: 0,
        translations_created: 0
      }

      templates = registered_templates(unique_templates(find_templates(paths)))

      ActiveRecord::Base.transaction do
        templates.each do |template|
          record = ::MailTemplate.find_or_initialize_by(name: template.name)

          if record.new_record?
            record.assign_attributes(template_params(template))
            record.save!
            result[:templates_created] += 1
          end

          template.variants.each do |variant|
            language = ensure_language!(variant.language)
            next if record.mail_template_translations.where(language:).exists?

            record.mail_template_translations.create!(
              translation_params(template, variant).merge(language:)
            )
            result[:translations_created] += 1
          end
        end
      end

      result
    end

    def self.default_from
      configured_support_mail || DEFAULT_FROM
    end

    def self.default_reply_to
      configured_support_mail
    end

    def self.default_return_path
      default_from
    end

    def self.default_template_paths
      paths = [File.join(VpsAdmin::API.root, 'notification_templates', 'templates')]

      VpsAdmin::API::Plugin.registered.each_value do |plugin|
        next unless plugin.directory

        paths << File.join(plugin.directory, 'notification_templates', 'templates')
      end

      paths
    end

    def self.find_templates(paths)
      paths.flat_map do |path|
        next [] unless Dir.exist?(path)

        NotificationTemplates::Directory.new(path).templates
      end
    end

    def self.template_params(template)
      options = template.template_options

      {
        name: template.name,
        label: options[:label] || humanize(template.name),
        template_id: template.id.to_s,
        user_visibility: visibility(options[:user_visibility])
      }
    end

    def self.translation_params(template, variant)
      options = variant.options

      {
        from: options.fetch(:from, default_from),
        reply_to: options.fetch(:reply_to, default_reply_to),
        return_path: options.fetch(:return_path, default_return_path),
        subject: variant.content(:subject) || options[:subject] || default_subject(template),
        text_plain: variant.content(:text),
        text_html: variant.content(:html)
      }
    end

    def self.default_subject(template)
      "[vpsAdmin] #{template.name.tr('_', ' ')}"
    end

    def self.visibility(value)
      if value.nil?
        'default'
      elsif value
        'visible'
      else
        'invisible'
      end
    end

    def self.humanize(str)
      str.tr('_', ' ').split.map(&:capitalize).join(' ')
    end

    def self.required_default_templates
      registered = ::MailTemplate.templates

      registered.filter_map do |id, desc|
        [id.to_s, id.to_s] unless desc[:name]
      end.to_h.merge(
        CONCRETE_DEFAULTS.filter_map do |name, template_id|
          next unless registered.has_key?(template_id)

          [name.to_s, template_id.to_s]
        end.to_h
      )
    end

    def self.configured_support_mail
      value = ::SysConfig.get(:core, :support_mail)
      value = value.to_s.strip
      value unless value.empty?
    rescue ActiveRecord::ActiveRecordError
      nil
    end

    def self.ensure_language!(code)
      label = LANGUAGE_LABELS.fetch(code, code)

      ::Language.find_or_initialize_by(code:).tap do |language|
        language.label = label if language.new_record? || language.label == code
        language.save! if language.changed?
      end
    end

    def self.unique_templates(templates)
      seen = {}

      templates.filter_map do |template|
        next if seen[template.name]

        seen[template.name] = true
        template
      end
    end

    def self.registered_templates(templates)
      registered = ::MailTemplate.templates
      templates.select { |template| registered.has_key?(template.id.to_sym) }
    end

    private_class_method :configured_support_mail,
                         :ensure_language!,
                         :unique_templates,
                         :registered_templates,
                         :template_params,
                         :translation_params,
                         :default_subject,
                         :visibility,
                         :humanize
  end
end
