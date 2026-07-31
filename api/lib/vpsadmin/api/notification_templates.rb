# frozen_string_literal: true

module VpsAdmin::API
  module NotificationTemplates
    DEFAULT_FROM = 'noreply@vpsadmin.invalid'
    LANGUAGE_LABELS = {
      'en' => 'English',
      'cs' => 'Česky'
    }.freeze
    PROTOCOLS = %w[email telegram sms].freeze
    MANAGED_SOURCE_CATEGORY = 'notifications'
    MANAGED_SOURCE_NAME = 'managed_templates_source_id'
    DEFAULT_TELEGRAM_HTML = '<%= telegram_notification_html if respond_to?(:telegram_notification_html) %>'

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

    class Meta
      TEMPLATE_OPTS = %i[label user_visibility].freeze
      VARIANT_OPTS = %i[from reply_to return_path subject options].freeze

      TEMPLATE_OPTS.each do |name|
        define_method(name) { |value| @template_opts[name] = value }
      end

      VARIANT_OPTS.each do |name|
        define_method(name) { |value| @defaults[name] = value }
      end

      attr_reader :id, :template_opts

      def initialize(id)
        @id = id
        @template_opts = {}
        @defaults = {}
        @language_defaults = {}
        @protocols = {}
      end

      def lang(code, &)
        context = VariantOptions.new
        context.instance_exec(&)
        @language_defaults[code.to_s] = context.opts
      end

      def protocol(name, &)
        protocol_name = name.to_s
        raise "unsupported template protocol '#{protocol_name}'" unless PROTOCOLS.include?(protocol_name)

        context = ProtocolOptions.new
        context.instance_exec(&)
        @protocols[protocol_name] = context
      end

      def variant_defaults(protocol, lang)
        protocol_meta = @protocols[protocol.to_s]
        @defaults
          .merge(@language_defaults.fetch(lang.to_s, {}))
          .merge(protocol_meta&.defaults || {})
          .merge(protocol_meta&.lang_opts(lang) || {})
      end
    end

    class VariantOptions
      attr_reader :opts

      def initialize
        @opts = {}
      end

      Meta::VARIANT_OPTS.each do |name|
        define_method(name) { |value| @opts[name] = value }
      end
    end

    class ProtocolOptions < VariantOptions
      attr_reader :defaults

      def initialize
        super
        @defaults = @opts
        @languages = {}
      end

      def lang(code, &)
        context = VariantOptions.new
        context.instance_exec(&)
        @languages[code.to_s] = context.opts
      end

      def lang_opts(code)
        @languages.fetch(code.to_s, {})
      end
    end

    class MetaContext
      attr_reader :meta

      def template(id = nil, &)
        @meta = Meta.new(id)
        @meta.instance_exec(&)
      end
    end

    class DirectoryTemplate
      attr_reader :name, :id, :variants

      def initialize(path)
        @path = path
        @name = File.basename(path)
        @variants = []

        meta_path = File.join(path, 'meta.rb')
        raise "#{meta_path} does not exist" unless File.exist?(meta_path)

        context = MetaContext.new
        context.instance_eval(File.read(meta_path), meta_path)

        @meta = context.meta || raise("#{meta_path} did not define template")
        @id = @meta.id || @name

        variant_files.each do |(protocol, lang), files|
          @variants << DirectoryVariant.new(self, protocol, lang, files)
        end
      end

      def params
        {
          name:,
          label: @meta.template_opts[:label] || humanize(name),
          template_id: id.to_s,
          user_visibility: visibility(@meta.template_opts[:user_visibility])
        }
      end

      def variant_defaults(protocol, lang)
        @meta.variant_defaults(protocol, lang)
      end

      private

      def variant_files
        files = {}

        PROTOCOLS.each do |protocol|
          protocol_dir = File.join(@path, protocol)
          next unless Dir.exist?(protocol_dir)

          Dir.glob(File.join(protocol_dir, '*.erb')).each do |file|
            parts = File.basename(file).split('.')
            raise "invalid template file #{file}" unless parts.length == 3 && parts.last == 'erb'

            lang = parts[0]
            format = parts[1]
            raise "invalid template format #{format} in #{file}" unless %w[subject text html].include?(format)

            files[[protocol, lang]] ||= []
            files[[protocol, lang]] << file
          end
        end

        files
      end

      def visibility(value)
        if value.nil?
          'default'
        elsif value
          'visible'
        else
          'invisible'
        end
      end

      def humanize(str)
        str.tr('_', ' ').split.map(&:capitalize).join(' ')
      end
    end

    class DirectoryVariant
      attr_reader :protocol, :lang, :formats

      def initialize(template, protocol, lang, files)
        @template = template
        @protocol = protocol
        @lang = lang
        @formats = []
        @content = {}

        files.each do |file|
          format = File.basename(file).split('.')[1]
          @content[format.to_sym] = File.read(file)
          @formats << format unless @formats.include?(format)
        end

        @formats.sort!
      end

      def params
        defaults = @template.variant_defaults(protocol, lang)

        {
          protocol:,
          from: defaults.fetch(:from, default_from),
          reply_to: defaults.fetch(:reply_to, default_reply_to),
          return_path: defaults.fetch(:return_path, default_return_path),
          subject: @content[:subject] || defaults[:subject] || default_subject,
          text: @content[:text],
          html: @content[:html] || default_html,
          options: defaults[:options] || {}
        }
      end

      private

      def default_subject
        return if protocol != 'email'

        "[vpsAdmin] #{@template.name.tr('_', ' ')}"
      end

      def default_html
        return unless protocol == 'telegram'

        DEFAULT_TELEGRAM_HTML
      end

      def default_from
        protocol == 'email' ? NotificationTemplates.default_from : nil
      end

      def default_reply_to
        protocol == 'email' ? NotificationTemplates.default_reply_to : nil
      end

      def default_return_path
        protocol == 'email' ? NotificationTemplates.default_return_path : nil
      end
    end

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
            record.assign_attributes(template.params)
            record.save!
            result[:templates_created] += 1
          end

          template.variants.each do |variant|
            language = ensure_language!(variant.lang)
            existing = record.notification_template_variants.find_by(
              language:,
              protocol: variant.protocol
            )

            if existing
              params = variant.params

              if backfill_telegram_html?(existing, params)
                existing.update!(html: params[:html])
                result[:variants_updated] += 1
              end

              next
            end

            record.notification_template_variants.create!(
              variant.params.merge(language:)
            )
            result[:variants_created] += 1
          end
        end
      end

      result
    end

    def self.install_managed!(paths:, source_id:)
      source_id = source_id.to_s.strip
      raise ArgumentError, 'source_id is required' if source_id.empty?

      paths = Array(paths).map(&:to_s).reject(&:blank?).map { |path| managed_template_path(path) }.uniq
      raise ArgumentError, 'at least one template path is required' if paths.empty?

      result = {
        source_id:,
        unchanged_source: false,
        templates_created: 0,
        templates_updated: 0,
        variants_created: 0,
        variants_updated: 0
      }

      with_managed_install_lock do |marker|
        if marker.value.to_s == source_id
          result[:unchanged_source] = true
          next
        end

        unique_templates(find_templates(paths)).each do |template|
          install_managed_template!(template, result)
        end

        marker.update!(value: source_id)
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

        Dir.children(path).sort.filter_map do |entry|
          template_path = File.join(path, entry)
          next unless Dir.exist?(template_path)
          next unless File.exist?(File.join(template_path, 'meta.rb'))

          DirectoryTemplate.new(template_path)
        end
      end
    end

    def self.managed_template_path(path)
      path = path.to_s
      nested = File.join(path, 'templates')

      Dir.exist?(nested) ? nested : path
    end

    def self.with_managed_install_lock
      ActiveRecord::Base.transaction do
        marker = managed_source_marker!
        marker.lock!
        yield marker
      end
    end

    def self.managed_source_marker!
      ::SysConfig.find_or_create_by!(
        category: MANAGED_SOURCE_CATEGORY,
        name: MANAGED_SOURCE_NAME
      )
    rescue ActiveRecord::RecordNotUnique
      ::SysConfig.find_by!(
        category: MANAGED_SOURCE_CATEGORY,
        name: MANAGED_SOURCE_NAME
      )
    end

    def self.install_managed_template!(template, result)
      record = ::NotificationTemplate.find_or_initialize_by(name: template.name)
      record.assign_attributes(template.params)

      if record.new_record?
        record.save!
        result[:templates_created] += 1
      elsif record.changed?
        record.save!
        result[:templates_updated] += 1
      end

      template.variants.each do |variant|
        language = ensure_language!(variant.lang)
        existing = record.notification_template_variants.find_or_initialize_by(
          language:,
          protocol: variant.protocol
        )
        existing.assign_attributes(variant.params.merge(language:))

        if existing.new_record?
          existing.save!
          result[:variants_created] += 1
        elsif existing.changed?
          existing.save!
          result[:variants_updated] += 1
        end
      end
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
      return false unless variant.protocol == 'telegram' && params[:html].present?

      variant.html.blank? && variant.text == params[:text]
    end

    def self.normalize_template_body(value)
      value.to_s.gsub(/\r\n?/, "\n").strip
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
                         :normalize_template_body,
                         :configured_support_mail,
                         :ensure_language!,
                         :unique_templates,
                         :registered_templates,
                         :managed_template_path,
                         :with_managed_install_lock,
                         :managed_source_marker!,
                         :install_managed_template!
  end
end
