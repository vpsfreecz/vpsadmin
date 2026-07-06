# frozen_string_literal: true

require_relative 'notification_templates'

module VpsAdmin::API
  module NotificationTemplateReconciler
    DEFAULT_FROM = 'noreply@vpsadmin.invalid'
    LANGUAGE_LABELS = {
      'en' => 'English',
      'cs' => 'Česky'
    }.freeze
    SOURCE_CATEGORY = 'notifications'
    SOURCE_NAME = 'template_source'

    CONCRETE_DEFAULTS = {
      expiration_user_active: :expiration_warning,
      expiration_vps_active: :expiration_warning,

      request_create_admin: :request_create_admin,
      request_create_user: :request_create_user,
      request_update_admin: :request_update_admin,
      request_update_user: :request_update_user,
      request_resolve_admin: :request_resolve_admin,
      request_resolve_user: :request_resolve_user,

      outage_report_generic: :outage_report_generic,
      outage_report_generic_announce: :outage_report_generic_announce,
      outage_report_generic_update: :outage_report_generic_update,
      outage_report_user: :outage_report_user,
      outage_report_user_announce: :outage_report_user_announce,
      outage_report_user_update: :outage_report_user_update,

      alert_monthly_traffic_closed: :alert_monthly_traffic_closed,
      alert_monthly_traffic_confirmed: :alert_monthly_traffic_confirmed,
      alert_unpaid_cpu_closed: :alert_unpaid_cpu_closed,
      alert_unpaid_cpu_confirmed: :alert_unpaid_cpu_confirmed,
      alert_unpaid_data_flow_closed: :alert_unpaid_data_flow_closed,
      alert_unpaid_data_flow_confirmed: :alert_unpaid_data_flow_confirmed,
      alert_diskspace_closed_hypervisor: :alert_diskspace_closed_hypervisor,
      alert_diskspace_closed_primary: :alert_diskspace_closed_primary,
      alert_diskspace_confirmed_hypervisor: :alert_diskspace_confirmed_hypervisor,
      alert_diskspace_confirmed_primary: :alert_diskspace_confirmed_primary,
      alert_dns_secondary_transfer_failure_closed: :alert_dns_secondary_transfer_failure_closed,
      alert_dns_secondary_transfer_failure_confirmed: :alert_dns_secondary_transfer_failure_confirmed,
      alert_outgoing_data_flow_closed: :alert_outgoing_data_flow_closed,
      alert_outgoing_data_flow_confirmed: :alert_outgoing_data_flow_confirmed,
      alert_paid_cpu_closed: :alert_paid_cpu_closed,
      alert_paid_cpu_confirmed: :alert_paid_cpu_confirmed,
      alert_vps_in_rescue: :alert_vps_in_rescue,
      alert_zombie_processes_closed: :alert_zombie_processes_closed,
      alert_zombie_processes_confirmed: :alert_zombie_processes_confirmed,
      alert_zombie_processes_restart: :alert_zombie_processes_restart,
      alert_vps_dataset_over_quota: :alert_vps_dataset_over_quota
    }.freeze

    def self.install_defaults!(paths: default_template_paths)
      result = {
        templates_created: 0,
        variants_created: 0,
        variants_updated: 0
      }

      templates = registered_templates(unique_templates(find_templates(paths)))

      ActiveRecord::Base.transaction do
        templates.each do |template|
          record = ::NotificationTemplate.find_or_initialize_by(name: template.name)

          if record.new_record?
            record.assign_attributes(template_params(template))
            record.save!
            result[:templates_created] += 1
          end

          template.variants.each do |variant|
            language = ensure_language!(variant.language)
            existing = record.notification_template_variants.find_by(
              language:,
              protocol: variant.protocol
            )

            if existing
              params = variant_params(template, variant)
              if backfill_telegram_html?(existing, params)
                existing.update!(html: params[:html])
                result[:variants_updated] += 1
              end

              next
            end

            record.notification_template_variants.create!(
              variant_params(template, variant).merge(language:)
            )
            result[:variants_created] += 1
          end
        end
      end

      result
    end

    def self.reconcile!(path:, source_id:)
      source_id = source_id.to_s.strip
      raise ArgumentError, 'source_id is required' if source_id.empty?

      templates = NotificationTemplates::Directory.new(path).templates

      result = {
        source_id:,
        templates_created: 0,
        templates_updated: 0,
        variants_created: 0,
        variants_updated: 0
      }

      with_reconciliation_lock do |marker|
        templates.each do |template|
          reconcile_template!(template, result)
        end

        marker.update!(value: source_id) if marker.value.to_s != source_id
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

    def self.with_reconciliation_lock
      ActiveRecord::Base.transaction(requires_new: true) do
        marker = source_marker!
        marker.lock!
        yield marker
      end
    end

    def self.source_marker!
      ::SysConfig.find_or_create_by!(
        category: SOURCE_CATEGORY,
        name: SOURCE_NAME
      )
    rescue ActiveRecord::RecordNotUnique
      ::SysConfig.find_by!(
        category: SOURCE_CATEGORY,
        name: SOURCE_NAME
      )
    end

    def self.reconcile_template!(template, result)
      record = ::NotificationTemplate.lock.find_or_initialize_by(name: template.name)
      record.assign_attributes(template_params(template))

      if record.new_record?
        record.save!
        result[:templates_created] += 1
      elsif record.changed?
        record.save!
        result[:templates_updated] += 1
      end

      template.variants.each do |variant|
        language = ensure_language!(variant.language)
        existing = record.notification_template_variants.lock.find_or_initialize_by(
          language:,
          protocol: variant.protocol
        )
        existing.assign_attributes(variant_params(template, variant).merge(language:))

        if existing.new_record?
          existing.save!
          result[:variants_created] += 1
        elsif existing.changed?
          existing.save!
          result[:variants_updated] += 1
        end
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

    def self.variant_params(template, variant)
      options = variant.options

      params = {
        protocol: variant.protocol,
        subject: variant.content(:subject),
        text: variant.content(:text),
        html: variant.content(:html),
        options: {}
      }

      return params unless variant.protocol == 'email'

      params.merge(
        from: options.fetch(:from, default_from),
        reply_to: options.fetch(:reply_to, default_reply_to),
        return_path: options.fetch(:return_path, default_return_path),
        subject: params[:subject] || options[:subject] || default_subject(template)
      )
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
      registered = ::NotificationTemplate.templates

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

    def self.backfill_telegram_html?(variant, params)
      variant.protocol == 'telegram' &&
        variant.html.blank? &&
        params[:html].present? &&
        variant.text == params[:text]
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
      registered = ::NotificationTemplate.templates
      templates.select { |template| registered.has_key?(template.id.to_sym) }
    end

    private_class_method :backfill_telegram_html?,
                         :configured_support_mail,
                         :ensure_language!,
                         :unique_templates,
                         :registered_templates,
                         :with_reconciliation_lock,
                         :source_marker!,
                         :reconcile_template!,
                         :template_params,
                         :variant_params,
                         :default_subject,
                         :visibility,
                         :humanize
  end
end
