# frozen_string_literal: true

module VpsAdmin::API
  module MailTemplates
    DEFAULT_FROM = 'noreply@vpsadmin.invalid'
    LANGUAGE_LABELS = {
      'en' => 'English'
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

    class Meta
      OPTS = %i[label from reply_to return_path subject user_visibility].freeze

      OPTS.each do |name|
        define_method(name) do |value|
          @opts[name] = value
        end
      end

      attr_reader :opts

      def initialize(id)
        @opts = { id: }
        @translations = {}
      end

      def lang(code, &)
        meta = self.class.new(@opts[:id])
        meta.instance_exec(&)
        @translations[code.to_s] = meta.opts
      end

      def [](key)
        @opts[key]
      end

      def lang_opts(lang)
        opts = @opts.except(:id)
        opts.merge(@translations.fetch(lang, {}))
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
      attr_reader :name, :id, :translations

      def initialize(path)
        @path = path
        @name = File.basename(path)
        @translations = []

        meta_path = File.join(path, 'meta.rb')
        raise "#{meta_path} does not exist" unless File.exist?(meta_path)

        context = MetaContext.new
        context.instance_eval(File.read(meta_path), meta_path)

        @meta = context.meta || raise("#{meta_path} did not define template")
        @id = @meta[:id] || @name

        translation_files.group_by { |file| File.basename(file).split('.').first }.each do |lang, files|
          @translations << DirectoryTranslation.new(self, lang, files)
        end
      end

      def params
        {
          name:,
          label: @meta[:label] || humanize(name),
          template_id: id.to_s,
          user_visibility: visibility(@meta[:user_visibility])
        }
      end

      def translation_defaults(lang)
        @meta.lang_opts(lang)
      end

      private

      def translation_files
        Dir.glob(File.join(@path, '*.erb'))
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

    class DirectoryTranslation
      attr_reader :lang

      def initialize(template, lang, files)
        @template = template
        @lang = lang
        @plain = nil
        @html = nil

        files.each do |file|
          case File.basename(file).split('.')[1]
          when 'plain'
            @plain = File.read(file)
          when 'html'
            @html = File.read(file)
          end
        end
      end

      def params
        defaults = @template.translation_defaults(lang)
        {
          from: defaults[:from] || DEFAULT_FROM,
          reply_to: defaults[:reply_to],
          return_path: defaults[:return_path],
          subject: defaults[:subject] || default_subject,
          text_plain: @plain,
          text_html: @html
        }
      end

      private

      def default_subject
        "[vpsAdmin] #{@template.name.tr('_', ' ')}"
      end
    end

    class GeneratedTemplate
      attr_reader :name, :id, :translations

      def initialize(name, template_id)
        @name = name.to_s
        @id = template_id.to_s
        @translations = [GeneratedTranslation.new(@name)]
      end

      def params
        {
          name:,
          label: name.tr('_', ' ').split.map(&:capitalize).join(' '),
          template_id: id,
          user_visibility: 'default'
        }
      end
    end

    class GeneratedTranslation
      attr_reader :lang

      def initialize(template_name)
        @template_name = template_name
        @lang = 'en'
      end

      def params
        {
          from: DEFAULT_FROM,
          subject: "[vpsAdmin] #{@template_name.tr('_', ' ')}",
          text_plain: <<~MAIL
            Hello,

            this is an automated vpsAdmin notification.

            Template: #{@template_name}
          MAIL
        }
      end
    end

    def self.install_defaults!(paths: default_template_paths)
      result = {
        templates_created: 0,
        translations_created: 0
      }

      templates = unique_templates(find_templates(paths) + generated_templates)

      ActiveRecord::Base.transaction do
        templates.each do |template|
          record = ::MailTemplate.find_or_initialize_by(name: template.name)

          if record.new_record?
            record.assign_attributes(template.params)
            record.save!
            result[:templates_created] += 1
          end

          template.translations.each do |translation|
            language = ensure_language!(translation.lang)
            next if record.mail_template_translations.where(language:).exists?

            record.mail_template_translations.create!(
              translation.params.merge(language:)
            )
            result[:translations_created] += 1
          end
        end
      end

      result
    end

    def self.default_template_paths
      paths = [File.join(VpsAdmin::API.root, 'mail_templates')]

      VpsAdmin::API::Plugin.registered.each_value do |plugin|
        next unless plugin.directory

        paths << File.join(plugin.directory, 'mail_templates')
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

    def self.generated_templates
      registered = ::MailTemplate.templates

      non_parameterized = registered.filter_map do |id, desc|
        GeneratedTemplate.new(id, id) unless desc[:name]
      end

      concrete = CONCRETE_DEFAULTS.filter_map do |name, template_id|
        next unless registered.has_key?(template_id)

        GeneratedTemplate.new(name, template_id)
      end

      non_parameterized + concrete
    end

    def self.ensure_language!(code)
      ::Language.find_or_create_by!(code:) do |language|
        language.label = LANGUAGE_LABELS.fetch(code, code)
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

    private_class_method :ensure_language!, :unique_templates
  end
end
