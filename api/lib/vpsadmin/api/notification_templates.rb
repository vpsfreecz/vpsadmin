# frozen_string_literal: true

require 'digest'

module VpsAdmin::API
  module NotificationTemplates
    DEFAULT_FROM = 'noreply@vpsadmin.invalid'
    LANGUAGE_LABELS = {
      'en' => 'English',
      'cs' => 'Česky'
    }.freeze
    PROTOCOLS = %w[email telegram sms].freeze
    DEFAULT_TELEGRAM_HTML = '<%= telegram_notification_html if respond_to?(:telegram_notification_html) %>'
    LEGACY_DEFAULT_TELEGRAM_HTML = [
      <<~'ERB',
        <% subject = if @event.vps
                       "VPS #{@event.vps.hostname} (##{@event.vps.id}): #{@event.subject}"
                     else
                       @event.subject.to_s
                     end -%>
        <b><%= ERB::Util.html_escape(subject) %></b>
        <% if @event.summary.present? -%>

        <%= ERB::Util.html_escape(@event.summary.to_s) %>
        <% end -%>
        <% url = if @event.vps
                   webui_url("?page=adminvps&action=info&veid=#{@event.vps.id}")
                 else
                   webui_url("?page=notifications&action=event_show&id=#{@event.id}")
                 end -%>
        <% if url.present? -%>

        Link: <a href="<%= ERB::Util.html_escape(url.to_s) %>">open in vpsAdmin</a>
        <% end -%>
      ERB
      <<~'ERB'
        <% vps_link = webui_link('open in vpsAdmin', "?page=adminvps&action=info&veid=#{@vps.id}") -%>
        <b>VPS <%= h(@vps.hostname) %> (#<%= @vps.id %>): resources changed</b>

        Current limits:
        CPU: <code><%= @vps.cpu %> cores, limit <%= @vps.cpu_limit || (@vps.cpu * 100) %> %</code>
        Memory: <code><%= @vps.memory %> MB</code>
        Swap: <code><%= @vps.swap %> MB</code>

        Reason: <%= h(@reason) %>
        <% if @admin -%>
        Changed by: <%= h(@admin.full_name) %>
        <% end -%>
        <% if vps_link.present? -%>

        Link: <%= vps_link %>
        <% end -%>
      ERB
    ].freeze
    LEGACY_TELEGRAM_LINK_LABEL_HTML_SHA256 = %w[
      170013ca0aeaf80c857e98ea5208b760de99f4f33eca21f06a4f443a5e8343f4
      4e2bd296419a628d19a832d4c1889ae2cbd81107e97f3056469e2305e91e1081
      5248a93474617fae24b777de95639206f24a7c6784eb547ff98812c1d90e17f4
      5c653c0a8bdc3ad5bc1458b44603ccd44725c0b1dfc7b540fa4989aeeaaef2cb
      60cd39c6351104b4a7a8aebc571b44c47919f5ecb22fe201061e6c6bed71e634
      6bb2b77c793508c951393c57a6d71d4d16c42a5fd2ef12416f9beebb3500c24f
      9524fa13cfc5d0426a8a2812acb101b19c4458b3be23ba79a202a5b3ec3d9b51
      9baa490db5e89c8480d45fc7ef04d0ebd861ae2f1833eb6515aec6e57a1e31c4
      9f00ad865aef50a5cc613617124352e24340bc433aa86e1a0a35e392986c397d
      abc31fdbe6226e1e25abce60a39b6befc210e5f186feec1bd6a6432e6a04d099
      b53d126efb98d7283941e40ca9b485b9b140247d102c29d6c961528d106d8807
      c319a489d85cc137ce6c5b72933cfa04e9d69481e90988fbc5bb1211a04a784b
      c64f6c82d47fbca9cb4261d722aa2d4be1753da3f8007875a105cea30546fe43
      d6e874a6d174911b2ba5a71380e130297a37d2421db20ad87cbb31eec9b073d4
      d9413d5c25a82865e6fcf42c40c114e84037efbf17568d6c2ffe425d8d8099af
      fc06c7e24aa4f20755d9ddb6c35ee4eddab020b6cd59cba5570fd5f14d1f1f6d
    ].freeze

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

        result[:variants_updated] += backfill_legacy_telegram_html_variants!
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

      (variant.html.blank? && variant.text == params[:text]) ||
        (default_telegram_html?(params[:html]) && legacy_telegram_html?(variant))
    end

    def self.backfill_legacy_telegram_html_variants!
      updated = 0

      ::NotificationTemplateVariant.where(protocol: :telegram).find_each do |variant|
        next unless legacy_telegram_html?(variant)

        variant.update!(html: DEFAULT_TELEGRAM_HTML)
        updated += 1
      end

      updated
    end

    def self.default_telegram_html?(html)
      normalize_template_body(html) == normalize_template_body(DEFAULT_TELEGRAM_HTML)
    end

    def self.legacy_telegram_html?(variant)
      html = variant.html

      LEGACY_DEFAULT_TELEGRAM_HTML.any? do |legacy|
        normalize_template_body(html) == normalize_template_body(legacy)
      end || legacy_telegram_link_label_html?(variant)
    end

    def self.legacy_telegram_link_label_html?(variant)
      html = normalize_template_body(variant.html)
      fingerprint = Digest::SHA256.hexdigest(html)

      LEGACY_TELEGRAM_LINK_LABEL_HTML_SHA256.include?(fingerprint)
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
                         :backfill_legacy_telegram_html_variants!,
                         :default_telegram_html?,
                         :legacy_telegram_html?,
                         :legacy_telegram_link_label_html?,
                         :normalize_template_body,
                         :configured_support_mail,
                         :ensure_language!,
                         :unique_templates,
                         :registered_templates
  end
end
