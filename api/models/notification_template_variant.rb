require 'redcarpet'

class NotificationTemplateVariant < ApplicationRecord
  belongs_to :language
  belongs_to :notification_template

  validates :notification_template, presence: true
  validates :language, presence: true
  validates :protocol, presence: true
  validates :language, uniqueness: { scope: %i[notification_template protocol] }
  validate :check_protocol_content

  enum :protocol, %i[email telegram sms], suffix: true
  serialize :options, coder: JSON

  has_paper_trail

  def normalized_subject
    normalize_subject(subject) if subject
  end

  class TemplateBuilder
    include ActiveSupport::NumberHelper

    TELEGRAM_MARKDOWN_TAGS = %w[
      a b blockquote code del em i ins pre s span strike strong tg-spoiler u
    ].freeze
    UNSAFE_MARKDOWN_URI_SCHEME = /\b(?:javascript|vbscript|data):/i

    def initialize(vars, time_zone: nil)
      @time_zone = time_zone

      vars.each do |k, v|
        instance_variable_set("@#{k}", v)
      end
    end

    def build(tpl)
      ERB.new(tpl, trim_mode: '-').result(binding)
    end

    def local_time(value, format = VpsAdmin::API::TimeZones::DEFAULT_TIME_FORMAT)
      VpsAdmin::API::TimeZones.format_time(value, time_zone: @time_zone, format:)
    end

    def local_date(value, format = VpsAdmin::API::TimeZones::DEFAULT_DATE_FORMAT)
      VpsAdmin::API::TimeZones.format_date(value, time_zone: @time_zone, format:)
    end

    def html_escape(value)
      ERB::Util.html_escape(value.to_s)
    end

    alias h html_escape

    def html_link(label, url)
      return if url.blank?

      %(<a href="#{html_escape(url)}">#{html_escape(label)}</a>)
    end

    def markdown_html(value)
      return '' if value.blank?

      self.class.markdown_renderer.render(value.to_s).gsub(UNSAFE_MARKDOWN_URI_SCHEME, '').strip
    end

    def markdown_telegram_html(value)
      return '' if value.blank?

      self.class.telegram_supported_html(markdown_html(value))
    end

    def webui_link(label, path = nil)
      html_link(label, webui_url(path))
    end

    def webui_url(path = nil)
      base_url = VpsAdmin::API::Events.webui_url
      return base_url if path.blank?

      "#{base_url}/#{path.to_s.delete_prefix('/')}"
    end

    def telegram_notification_html
      return telegram_vps_resource_change_html if @notification_template_name.to_s == 'vps_resources_change'

      lines = [telegram_title]
      detail_lines = telegram_detail_lines.compact
      if detail_lines.any?
        lines << ''
        lines.concat(detail_lines)
      end

      link_line = telegram_primary_link_line
      if link_line.present?
        lines << ''
        lines << link_line
      end

      lines.compact.join("\n")
    end

    def webui_object_link(label, path)
      url = webui_object_url(path)
      return html_escape(label) if url.blank?

      html_link(label, url)
    end

    def webui_object_url(path)
      base_url = VpsAdmin::API::Events.webui_url
      return if base_url.blank? || path.blank?

      "#{base_url}/#{path.to_s.delete_prefix('/')}"
    end

    def webui_vps_link(vps = telegram_vps)
      return unless vps

      webui_object_link(telegram_vps_label(vps), telegram_vps_path(vps))
    end

    def webui_user_link(user = @user)
      return unless user.respond_to?(:id)

      label = user.respond_to?(:login) ? user.login : "user ##{user.id}"
      webui_object_link(label, "?page=adminm&action=edit&id=#{user.id}")
    end

    def webui_event_link(label = 'event details')
      event = telegram_event
      return unless event.respond_to?(:id)

      webui_object_link(label, "?page=notifications&action=event_show&id=#{event.id}")
    end

    def webui_security_advisory_link(advisory = @a || @advisory)
      return unless advisory.respond_to?(:id)

      label = "security advisory ##{advisory.id}"
      webui_object_link(label, "?page=security_advisory&action=show&id=#{advisory.id}")
    end

    def webui_snapshot_download_link(download = @dl)
      return unless download.respond_to?(:id)

      webui_object_link('snapshot download', "?page=backup&action=download_link&id=#{download.id}")
    end

    class << self
      def markdown_renderer
        @markdown_renderer ||= Redcarpet::Markdown.new(
          Redcarpet::Render::HTML.new(
            filter_html: true,
            no_images: true,
            no_styles: true,
            safe_links_only: true
          ),
          autolink: true,
          fenced_code_blocks: true,
          strikethrough: true
        )
      end

      def telegram_supported_html(html)
        html = html.to_s.dup
        html.gsub!(%r{<h[1-6]>(.*?)</h[1-6]>}im) { "<b>#{Regexp.last_match(1)}</b>\n" }
        html.gsub!(%r{</?p>}i, "\n")
        html.gsub!(%r{<br\s*/?>}i, "\n")
        html.gsub!(%r{</?(ul|ol)>}i, "\n")
        html.gsub!(/<li>/i, '- ')
        html.gsub!(%r{</li>}i, "\n")

        html.gsub!(%r{<(/?)([a-zA-Z][\w-]*)(?:\s+[^>]*)?>}) do |tag|
          closing = Regexp.last_match(1) == '/'
          name = Regexp.last_match(2).downcase

          next '' unless TELEGRAM_MARKDOWN_TAGS.include?(name)
          next "</#{name}>" if closing

          if name == 'a'
            href = tag[/\shref=(["'])(.*?)\1/i, 2]
            next '' unless safe_telegram_href?(href)

            %(<a href="#{ERB::Util.html_escape(href)}">)
          elsif name == 'span'
            tag.match?(/\sclass=(["'])tg-spoiler\1/i) ? '<span class="tg-spoiler">' : ''
          else
            "<#{name}>"
          end
        end

        html.gsub(/\r\n?/, "\n")
            .lines
            .map(&:rstrip)
            .join("\n")
            .gsub(/\n{3,}/, "\n\n")
            .strip
      end

      def safe_telegram_href?(href)
        href.to_s.match?(%r{\Ahttps?://}i) || href.to_s.match?(/\Amailto:/i)
      end
    end

    private

    def telegram_event
      return @notification_event if @notification_event.respond_to?(:event_type)

      @event if @event.respond_to?(:event_type)
    end

    def telegram_vps
      @vps || telegram_event&.vps
    end

    def telegram_title
      subject = telegram_subject

      title = if telegram_vps
                "#{html_escape(telegram_vps_subject(subject))}: #{webui_vps_link}"
              elsif @a || @advisory
                "#{html_escape(subject)}: #{webui_security_advisory_link}"
              elsif @dl
                "#{html_escape(subject)}: #{webui_snapshot_download_link}"
              elsif @user.respond_to?(:id)
                "#{html_escape(subject)}: #{webui_user_link}"
              else
                html_escape(subject)
              end

      "<b>#{title}</b>"
    end

    def telegram_subject
      event = telegram_event
      subject = event&.subject
      subject ||= @event.label if @event.respond_to?(:label)
      subject ||= @notification_template&.label if @notification_template.respond_to?(:label)
      subject ||= @notification_template_name.to_s.tr('_', ' ')
      subject.to_s.presence || 'Notification'
    end

    def telegram_vps_subject(subject)
      subject.to_s
             .sub(/\AVPS\s+#?\d+\s*/i, 'VPS ')
             .sub(/\s+for\s+VPS\s+#?\d+\s*\z/i, '')
             .strip
             .presence || 'VPS notification'
    end

    def telegram_vps_label(vps)
      hostname = vps.respond_to?(:hostname) ? vps.hostname : nil
      id = vps.respond_to?(:id) ? vps.id : nil

      if hostname.present? && id.present?
        "#{hostname} (##{id})"
      elsif hostname.present?
        hostname
      elsif id.present?
        "VPS ##{id}"
      else
        'VPS'
      end
    end

    def telegram_vps_path(vps)
      return unless vps.respond_to?(:id) && vps.id.present?

      "?page=adminvps&action=info&veid=#{vps.id}"
    end

    def telegram_detail_lines
      lines = []
      lines << telegram_summary_line
      lines.concat(telegram_user_security_lines)
      lines.concat(telegram_vps_resource_lines)
      lines.concat(telegram_state_lines)
      lines.concat(telegram_vps_migration_lines)
      lines.concat(telegram_dns_resolver_lines)
      lines.concat(telegram_dataset_lines)
      lines.concat(telegram_snapshot_download_lines)
      lines.concat(telegram_oom_lines)
      lines.concat(telegram_incident_lines)
      lines.concat(telegram_security_advisory_lines)
      lines.concat(telegram_monitoring_alert_lines)
      lines.concat(telegram_daily_report_lines)
      reason_line = telegram_reason_line(@reason)
      lines << reason_line if reason_line.present? && !lines.include?(reason_line)

      lines.compact
    end

    def telegram_summary_line
      summary = telegram_event&.summary
      return if summary.blank?
      return if summary == @reason

      html_escape(summary)
    end

    def telegram_user_security_lines
      lines = []

      if @user_session
        lines << telegram_field('Time', local_time(@user_session.created_at, '%Y-%m-%d %H:%M %Z'))
        ip = @user_session.client_ip_addr || @user_session.api_ip_addr
        lines << telegram_field('IP address', ip || 'unknown')
        lines << telegram_field('Client', @user_session.client_version)
        lines << telegram_field('Scope', @user_session.scope_str) if @user_session.respond_to?(:scope_str)
      end

      if @user_device
        lines << telegram_field('Device address', @user_device.client_ip_addr)
        lines << telegram_field('User agent', @user_device.user_agent_string)
      end

      if @totp_device
        lines << telegram_field('Device', @totp_device.label)
        lines << telegram_field('Time', local_time(@time, '%Y-%m-%d %H:%M %Z')) if @time
      end

      lines << telegram_field('IP address', @request.ip) if @request.respond_to?(:ip)

      groups = @attempt_groups || @attempts
      if groups.present?
        lines << '<b>Failed attempts:</b>'
        Array(groups).each_with_index do |group, index|
          lines << html_escape("Group #{index + 1}:")
          Array(group).first(5).each do |attempt|
            lines << html_escape(telegram_failed_login_label(attempt))
          end
        end
      end

      lines
    end

    def telegram_failed_login_label(attempt)
      time = local_time(attempt.created_at, '%Y-%m-%d %H:%M %Z')
      ip = attempt.client_ip_addr || attempt.api_ip_addr || 'unknown IP'
      "- #{time}, #{attempt.auth_type}, #{ip}, #{attempt.reason}"
    end

    def telegram_vps_resource_lines
      return [] unless @notification_template_name.to_s == 'vps_resources_change'

      []
    end

    def telegram_vps_resource_change_html
      lines = [
        telegram_title,
        '',
        '<b>Current limits:</b>',
        "CPU: <code>#{html_escape(telegram_cpu_limit_summary)}</code>",
        "Memory: <code>#{html_escape("#{telegram_resource_raw('memory')} MB")}</code>",
        "Swap: <code>#{html_escape("#{telegram_resource_raw('swap')} MB")}</code>"
      ]

      reason_line = telegram_reason_line(@reason)
      changed_by_line = telegram_changed_by_line
      if reason_line.present? || changed_by_line.present?
        lines << ''
        lines << reason_line if reason_line.present?
        lines << changed_by_line if changed_by_line.present?
      end

      link_line = telegram_primary_link_line
      if link_line.present?
        lines << ''
        lines << link_line
      end

      lines.compact.join("\n")
    end

    def telegram_resource_value(name)
      value = telegram_resource_raw(name)

      case name.to_s
      when 'cpu_limit'
        value.to_i <= 0 ? 'unlimited' : value
      when 'memory', 'swap'
        number_to_human_size(value.to_i * 1024 * 1024)
      else
        value
      end
    end

    def telegram_resource_raw(name)
      value = telegram_param(name)
      value = telegram_vps.public_send(name) if value.nil? && telegram_vps.respond_to?(name)
      value
    end

    def telegram_cpu_limit_summary
      cpu = telegram_resource_raw('cpu')
      limit = telegram_vps.cpu_limit || (cpu.to_i * 100)

      "#{cpu} cores, limit #{limit} %"
    end

    def telegram_changed_by_line
      changed_by = @admin.respond_to?(:full_name) ? @admin.full_name : nil
      changed_by = @admin.login if changed_by.blank? && @admin.respond_to?(:login)
      changed_by ||= 'vpsAdmin'

      telegram_field('Changed by', changed_by)
    end

    def telegram_state_lines
      lines = []
      state = @state
      lines << telegram_field('State', state.state) if state.respond_to?(:state) && state.state.present?
      lines << telegram_reason_line(state.reason) if state.respond_to?(:reason)

      if state.respond_to?(:expiration_date) && state.expiration_date
        lines << telegram_field('Expiration', local_time(state.expiration_date, '%Y-%m-%d %H:%M %Z'))
      end

      if defined?(@expires_in_a_day) && @expires_in_a_day
        lines << 'Expires in less than one day.'
      elsif defined?(@expires_in_days) && @expires_in_days && @expires_in_days >= 0
        lines << html_escape("Expires in approximately #{@expires_in_days.ceil} days.")
      elsif defined?(@expired_days_ago) && @expired_days_ago
        lines << html_escape("Expired approximately #{@expired_days_ago.ceil} days ago.")
      end

      lines
    end

    def telegram_vps_migration_lines
      lines = []
      lines << telegram_field('From', @src_node.domain_name) if @src_node.respond_to?(:domain_name)
      lines << telegram_field('To', @dst_node.domain_name) if @dst_node.respond_to?(:domain_name)
      if defined?(@maintenance_window)
        lines << telegram_field('Maintenance window', @maintenance_window ? 'yes' : 'no')
      end
      lines
    end

    def telegram_dns_resolver_lines
      lines = []
      if @old_dns_resolver
        lines << telegram_field('Previous resolver', telegram_dns_resolver_label(@old_dns_resolver))
      end
      lines << telegram_field('New resolver', telegram_dns_resolver_label(@new_dns_resolver)) if @new_dns_resolver
      lines
    end

    def telegram_dns_resolver_label(resolver)
      addrs = resolver.respond_to?(:addrs) ? resolver.addrs : nil
      label = resolver.respond_to?(:label) ? resolver.label : resolver.to_s
      addrs.present? ? "#{label} (#{addrs})" : label
    end

    def telegram_dataset_lines
      lines = []
      lines << telegram_field('Dataset', @dataset.full_name) if @dataset.respond_to?(:full_name)

      if @expansion.respond_to?(:added_space)
        label = if @notification_template_name.to_s == 'vps_dataset_shrunk'
                  'Removed space'
                elsif @notification_template_name.to_s == 'alert_vps_dataset_over_quota'
                  'Temporary expansion'
                else
                  'Added space'
                end
        lines << telegram_field(label, "#{@expansion.added_space} MiB")
      end

      lines << telegram_field('From pool', @src_pool.filesystem) if @src_pool.respond_to?(:filesystem)
      lines << telegram_field('To pool', @dst_pool.filesystem) if @dst_pool.respond_to?(:filesystem)
      lines << telegram_field('Exports', @exports.count) if @exports
      lines << telegram_field('Restart VPS', @restart_vps ? 'yes' : 'no') if defined?(@restart_vps)

      if @vpses.present?
        lines << '<b>Affected VPS:</b>'
        Array(@vpses).first(10).each do |vps|
          lines << "- #{webui_object_link(telegram_vps_label(vps), telegram_vps_path(vps))}"
        end
      end

      lines
    end

    def telegram_snapshot_download_lines
      return [] unless @dl

      snapshot = @dl.snapshot if @dl.respond_to?(:snapshot)
      dataset = snapshot.dataset if snapshot.respond_to?(:dataset)
      lines = []
      if dataset && snapshot
        lines << telegram_field('Snapshot', "#{dataset.full_name}@#{snapshot.name}")
      end
      lines << telegram_field('File', @dl.file_name) if @dl.respond_to?(:file_name)
      if @dl.respond_to?(:expiration_date) && @dl.expiration_date
        lines << telegram_field('Available until', local_time(@dl.expiration_date, '%Y-%m-%d %H:%M %Z'))
      end
      lines
    end

    def telegram_oom_lines
      lines = []
      if defined?(@selected_oom_count) && defined?(@all_oom_count)
        lines << telegram_field('Selected events', "#{@selected_oom_count} of #{@all_oom_count}")
      end

      Array(@selected_oom_reports).first(10).each do |report|
        lines << html_escape(telegram_oom_report_label(report))
      end

      if defined?(@all_oom_count) && defined?(@selected_oom_count) && @all_oom_count.to_i > @selected_oom_count.to_i
        lines << html_escape("There are #{@all_oom_count.to_i - @selected_oom_count.to_i} additional events not shown here.")
      end

      lines << telegram_field('Events in period', @ooms_in_period) if defined?(@ooms_in_period)
      lines << telegram_field('Period', "#{@period_seconds} seconds") if defined?(@period_seconds)
      lines << telegram_field('Action', @action) if defined?(@action)
      lines
    end

    def telegram_oom_report_label(report)
      time = local_time(report.created_at, '%Y-%m-%d %H:%M %Z')
      killed = report.killed_name || 'unknown'
      killed = "#{killed}[#{report.killed_pid}]" if report.killed_pid
      "- #{time}: invoked by #{report.invoked_by_name}[#{report.invoked_by_pid}], killed #{killed}, count #{report.count}"
    end

    def telegram_incident_lines
      return [] unless @incident

      lines = []
      lines << telegram_field('Subject', @incident.subject)
      if @incident.respond_to?(:detected_at) && @incident.detected_at
        lines << telegram_field('Detected at', local_time(@incident.detected_at, '%Y-%m-%d %H:%M %Z'))
      end
      lines << telegram_field('IP address', @incident.ip_address) if @incident.respond_to?(:ip_address)
      lines << telegram_field('Action', @incident.vps_action) if @incident.respond_to?(:vps_action)
      lines << html_escape(@incident.text) if @incident.respond_to?(:text) && @incident.text.present?
      lines
    end

    def telegram_security_advisory_lines
      advisory = @a || @advisory
      return [] unless advisory

      lines = []
      lines << telegram_field('CVEs', advisory.cves) if advisory.respond_to?(:cves)
      if advisory.respond_to?(:published_at) && advisory.published_at
        lines << telegram_field('Published at', local_time(advisory.published_at, '%Y-%m-%d %H:%M %Z'))
      end

      lines << html_escape(@update.en_summary) if @update.respond_to?(:en_summary) && @update.en_summary.present?
      lines << html_escape(@update.en_message) if @update.respond_to?(:en_message) && @update.en_message.present?
      lines << html_escape(advisory.en_summary) if advisory.respond_to?(:en_summary) && advisory.en_summary.present?
      lines << html_escape(advisory.en_response) if advisory.respond_to?(:en_response) && advisory.en_response.present?

      if @vpses.present?
        lines << '<b>Affected VPS:</b>'
        Array(@vpses).first(10).each do |row|
          vps = row.respond_to?(:vps) ? row.vps : row
          node = row.respond_to?(:node) && row.node ? " on #{row.node.domain_name}" : ''
          lines << "- #{webui_object_link(telegram_vps_label(vps), telegram_vps_path(vps))}#{html_escape(node)}"
        end
      end

      lines
    end

    def telegram_monitoring_alert_lines
      alert = @event unless @event.respond_to?(:event_type)
      return [] unless alert

      lines = []
      lines << telegram_field('Alert', alert.label) if alert.respond_to?(:label)
      lines << telegram_field('State', alert.state) if alert.respond_to?(:state)
      lines << telegram_field('Issue', alert.issue) if alert.respond_to?(:issue)

      if @object
        lines << telegram_field('Object', telegram_object_label(@object))
      elsif alert.respond_to?(:class_name) && alert.respond_to?(:row_id)
        lines << telegram_field('Object', "#{alert.class_name} ##{alert.row_id}")
      end

      lines << telegram_field('Pool role', @dip.pool.role) if @dip.respond_to?(:pool) && @dip.pool
      lines << telegram_field('Current count', @zombie_process_count) if defined?(@zombie_process_count)
      lines << telegram_field('Threshold', @threshold) if defined?(@threshold)
      lines << telegram_field('Maintenance finish weekday', @finish_weekday) if defined?(@finish_weekday)
      lines << telegram_field('Maintenance finish minute', @finish_minutes) if defined?(@finish_minutes)
      lines
    end

    def telegram_object_label(object)
      %i[hostname full_name name label].each do |method|
        value = object.public_send(method) if object.respond_to?(method)
        return value.to_s if value.present?
      end

      object.respond_to?(:id) ? "#{object.class.name} ##{object.id}" : object.to_s
    end

    def telegram_daily_report_lines
      return [] unless @notification_template_name.to_s == 'daily_report'

      lines = []
      if @date
        period = "#{local_time(@date[:start], '%Y-%m-%d %H:%M %Z')} - " \
                 "#{local_time(@date[:end], '%Y-%m-%d %H:%M %Z')}"
        lines << telegram_field('Period', period)
      end

      lines << telegram_report_group('Users', @users)
      lines << telegram_report_group('VPS', @vps)
      lines << telegram_report_group('Storage', @datasets && {
                                       datasets: @datasets[:all]&.count,
                                       snapshots: @snapshots && "#{@snapshots[:all].count} total, #{@snapshots[:new].count} new",
                                       downloads: @downloads && "#{@downloads[:all].count} total, #{@downloads[:new].count} new"
                                     })
      lines << telegram_report_group('Transactions', @chains && {
                                       chains: "#{@chains[:total].count} total, #{@chains[:all_failed].count} failed",
                                       transactions: "#{@transactions[:total].count} total, #{@transactions[:failed].count} failed, " \
                                                     "#{@transactions[:warning].count} warning, #{@transactions[:pending].count} pending"
                                     })
      lines
    end

    def telegram_report_group(label, data)
      return unless data

      values = data.filter_map do |key, value|
        text = if value.is_a?(Hash) && value[:all] && value[:changed]
                 "#{value[:all].count} total, #{value[:changed].count} changed"
               elsif value.is_a?(Hash) && value[:changed]
                 value[:changed].count
               else
                 value
               end
        next if text.blank?

        "#{key.to_s.tr('_', ' ')}: #{text}"
      end
      return if values.empty?

      "<b>#{html_escape(label)}:</b>\n#{values.map { |v| html_escape("- #{v}") }.join("\n")}"
    end

    def telegram_primary_link_line
      target = telegram_primary_link
      return unless target

      label, path = target
      url = webui_object_url(path)
      "Link: #{html_link(label, url)}" if url.present?
    end

    def telegram_primary_link
      if @dl.respond_to?(:id)
        ['snapshot download', "?page=backup&action=download_link&id=#{@dl.id}"]
      elsif (@a || @advisory).respond_to?(:id)
        advisory = @a || @advisory
        ['security advisory', "?page=security_advisory&action=show&id=#{advisory.id}"]
      elsif telegram_vps.respond_to?(:id)
        ['VPS details', telegram_vps_path(telegram_vps)]
      elsif @user.respond_to?(:id)
        ['user details', "?page=adminm&action=edit&id=#{@user.id}"]
      elsif telegram_event.respond_to?(:id)
        ['event details', "?page=notifications&action=event_show&id=#{telegram_event.id}"]
      end
    end

    def telegram_field(label, value)
      return if value.blank?

      "#{html_escape(label)}: #{html_escape(value)}"
    end

    def telegram_reason_line(value)
      return if value.blank?

      "Reason: #{markdown_telegram_html(value)}"
    end

    def telegram_param(name)
      params = @parameters || telegram_event&.parameters || {}
      params[name.to_s] || params[name.to_sym]
    end
  end

  def resolve(vars, time_zone: nil)
    b = TemplateBuilder.new(vars, time_zone:)
    self.subject = normalize_subject(b.build(subject)) if subject
    self.text = b.build(text) if text
    self.html = b.build(html) if html
  end

  private

  def normalize_subject(value)
    value.to_s.gsub(/[\r\n]+/, ' ').strip
  end

  protected

  def check_protocol_content
    case protocol&.to_sym
    when :email
      errors.add(:from, "can't be blank") if from.blank?
      errors.add(:subject, "can't be blank") if subject.blank?
      errors.add(:text, 'or html must be present') if text.blank? && html.blank?
    when :telegram, :sms
      errors.add(:text, "can't be blank") if text.blank?
    end
  end
end
