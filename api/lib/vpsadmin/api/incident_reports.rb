require 'uri'
require 'time'

module VpsAdmin::API
  module IncidentReports
    def self.with_language(user, &)
      locale = user.language&.code&.to_sym
      locale = VpsAdmin::API::I18n::DEFAULT_LOCALE unless VpsAdmin::API::I18n.available_locales.include?(locale)
      ::I18n.with_locale(locale, &)
    end

    def self.webui_url(**query)
      base = SysConfig.get(:webui, :base_url).to_s
      return if base.empty?

      uri = URI.parse(base)
      return unless %w[https http].include?(uri.scheme) && uri.host && !uri.userinfo && !uri.fragment

      uri.query = URI.encode_www_form(query)
      uri.to_s
    rescue URI::InvalidURIError
      nil
    end

    def self.mail_policies(incident, language: :en)
      incident.incident_policy_evaluations.sort_by(&:policy_key).filter_map do |evaluation|
        evaluation.mail_summary(language:)
      end
    end

    def self.escalation_message(action)
      with_language(action.user) do
        labels = action.saved_policy_evaluation.fetch('metadata').fetch('labels')
        label = labels.fetch(::I18n.locale.to_s) { labels.fetch('en') }
        if action.kind == 'warning'
          subject = VpsAdmin::API::I18n.t('incident_reports.notices.warning.subject')
          text = VpsAdmin::API::I18n.t('incident_reports.notices.warning.text', vps_id: action.vps_id,
                                                                                trigger_id: action.incident_report_id)
        else
          subject = VpsAdmin::API::I18n.t('incident_reports.notices.stop_completed.subject')
          text = VpsAdmin::API::I18n.t('incident_reports.notices.stop_completed.text', vps_id: action.vps_id,
                                                                                       trigger_id: action.incident_report_id)
        end
        { subject: "#{subject}: #{label}", text: "#{label}\n\n#{text}\n" }
      end
    end

    def self.oomd_event_message(vps:, user:, action:)
      locale = user.language&.code&.to_sym
      locale = VpsAdmin::API::I18n::DEFAULT_LOCALE unless VpsAdmin::API::I18n.available_locales.include?(locale)

      ::I18n.with_locale(locale) do
        case action
        when 'stop'
          {
            subject: VpsAdmin::API::I18n.t('incident_reports.oomd.stop.subject'),
            text: VpsAdmin::API::I18n.t('incident_reports.oomd.stop.text', vps_id: vps.id, hostname: vps.hostname)
          }
        when 'restart'
          {
            subject: VpsAdmin::API::I18n.t('incident_reports.oomd.restart.subject'),
            text: VpsAdmin::API::I18n.t('incident_reports.oomd.restart.text', vps_id: vps.id, hostname: vps.hostname)
          }
        else
          raise ArgumentError, "Unsupported oomd action #{action.inspect}"
        end
      end
    end

    def self.vps_evidence_mail_projection(incident)
      snapshot = incident.evidence_snapshot
      return unless snapshot

      rows = incident.vps_evidence_intervals.order(:from_at, :id).limit(5).map do |row|
        { from_at: row.from_at, to_at: row.to_at, credit_us: row.credit_us, measurement: row.measurement, peak_unit: row.peak_unit, peak_value: row.peak_value,
          peak_is_lower_bound: row.peak_is_lower_bound }
      end
      snapshot.symbolize_keys.merge(condition: snapshot['condition']&.symbolize_keys, intervals: rows, shown_count: rows.length,
                                    total_count: snapshot.fetch('interval_count'), omitted_count: snapshot.fetch('interval_count') - rows.length,
                                    detail_url: webui_url(page: 'incidents', action: 'show', id: incident.id))
    end

    def self.rtnl_event_message(vps:, user:, snapshot:, intervals:)
      with_language(user) do
        values = snapshot.symbolize_keys.merge(vps_id: vps.id, hostname: vps.hostname,
                                               credit_seconds: snapshot.fetch('credit_us') / 1_000_000.0,
                                               cutoff_seconds: snapshot.fetch('condition').fetch('value') / 1_000_000.0,
                                               qualification_seconds: snapshot.fetch('qualification_interval_us') / 1_000_000.0,
                                               shown: intervals.length, total: snapshot.fetch('interval_count'))
        lines = [VpsAdmin::API::I18n.t('incident_reports.rtnl.text', **values)]
        lines << VpsAdmin::API::I18n.t('incident_reports.rtnl.incomplete') unless snapshot.fetch('window_complete')
        lines << VpsAdmin::API::I18n.t('incident_reports.rtnl.counts', **values)
        intervals.each do |interval|
          lines << VpsAdmin::API::I18n.t('incident_reports.rtnl.interval', from: interval.fetch(:from_at).iso8601(6),
                                                                           to: interval.fetch(:to_at).iso8601(6),
                                                                           credit: interval.fetch(:credit_us) / 1_000_000.0,
                                                                           peak: interval.fetch(:peak_value) / 1_000_000.0,
                                                                           lower_bound: interval[:peak_is_lower_bound] ? '≥' : '')
        end
        { subject: VpsAdmin::API::I18n.t('incident_reports.rtnl.subject'), text: "#{lines.join("\n\n")}\n" }
      end
    end

    # Entry point for incoming messages
    class Handler
      # @param mailbox [::Mailbox]
      def initialize(mailbox)
        @mailbox = mailbox
      end

      # @param message [Mail::Message]
      # @param dry_run [Boolean]
      def handle_message(message, dry_run:)
        result = IncidentReports.handle_message(@mailbox, message, dry_run:)
        return false if result.nil?

        result.incidents.each do |inc|
          puts "Incident ##{inc.id} user=#{inc.user_id} vps=#{inc.vps_id} ip=#{inc.ip_address_assignment && inc.ip_address_assignment.ip_address}"
        end

        return result.processed? if dry_run

        if result.active.any?
          TransactionChains::IncidentReport::Send.fire(result, message:)
        elsif result.incidents.any? && result.reply
          TransactionChains::IncidentReport::Reply.fire(message, result)
        end

        result.processed?
      end
    end

    # Returned by incident report block handler
    class Result
      # @return [Array<::IncidentReport>]
      attr_reader :incidents

      # @return [Array<::IncidentReport>]
      attr_reader :active

      # @return [Boolean]
      attr_reader :processed
      alias processed? processed

      # @return [Hash]
      attr_reader :reply

      # @param incidents [Array<::IncidentReport>]
      # @param reply [Hash]
      # @option reply [String] :from
      # @option reply [Array<String>] :to
      # @param processed [Boolean, nil]
      def initialize(incidents:, reply: nil, processed: nil)
        @incidents = incidents.reject(&:policy_notice?)
        @active = @incidents.select do |inc|
          inc.user && inc.user.object_state == 'active' \
            && inc.vps && inc.vps.object_state == 'active'
        end
        @reply = reply
        @processed = processed.nil? ? @incidents.any? : processed
      end
    end

    class Config
      def initialize(&)
        instance_exec(&)
      end

      # @yieldparam mailbox [Mailbox]
      # @yieldparam message [Mail::Message]
      # @yieldreturn [Result, nil]
      def handle_message(&block)
        @handle_message = block
      end

      private

      def do_handle_message(mailbox, message, dry_run:)
        @handle_message.call(mailbox, message, dry_run:)
      end
    end

    class Parser
      # @return [::Mailbox]
      attr_reader :mailbox

      # @return [Mail::Message]
      attr_reader :message

      # @return [Boolean]
      attr_reader :dry_run
      alias dry_run? dry_run

      # @param mailbox [::Mailbox]
      # @param message [Mail::Message]
      # @param dry_run [Boolean]
      def initialize(mailbox, message, dry_run:)
        @mailbox = mailbox
        @message = message
        @dry_run = dry_run
      end

      protected

      # @param addr_str [String]
      # @param time [Time, nil]
      # @return [::IpAddressAssignment, nil]
      def find_ip_address_assignment(addr_str, time: nil)
        time ||= Time.now
        addr = IPAddress.parse(addr_str)

        # First we try a direct match which will work in most cases
        ip = ::IpAddress.find_by(ip_addr: addr.to_s, prefix: addr.prefix.to_i)

        # No direct match, the address could be from a larger network, we have to
        # search them one by one. This is rather slow and we should optimize it
        # in the future.
        if ip.nil?
          network = ::Network.where(ip_version: addr.ipv4? ? 4 : 6).detect do |net|
            net.include?(addr)
          end

          return if network.nil?

          ip = network.ip_addresses.detect { |net_ip| net_ip.include?(addr) }
        end

        # No match
        return if ip.nil?

        assignments = ::IpAddressAssignment.arel_table

        ip.ip_address_assignments
          .where(
            assignments[:from_date].lteq(time).and(
              assignments[:to_date].gteq(time).or(assignments[:to_date].eq(nil))
            )
          )
          .order('id DESC')
          .take
      end
    end

    def self.config(&)
      @config = Config.new(&)
    end

    def self.handle_message(mailbox, message, dry_run:)
      @config.send(:do_handle_message, mailbox, message, dry_run:)
    end
  end
end
