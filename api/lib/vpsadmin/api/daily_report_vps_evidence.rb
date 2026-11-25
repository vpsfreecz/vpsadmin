require 'uri'
require 'time'

module VpsAdmin::API
  # Receipt-time gains are materialized with the ordinary administrator report.
  # Original owner epochs remain distinct even after a transfer or deletion.
  class DailyReportVpsEvidence
    def initialize(from:, to:, generated_at: to, base_url: nil, language: :en)
      raise ArgumentError, 'Invalid evidence report period' unless from < to

      @from = from.utc
      @to = to.utc
      @generated_at = generated_at.utc
      @language = language.to_s
      @base = safe_base_url(base_url)
    end

    def vars
      rows = gain_rows
      totals = rows.group_by { |row| row[:signal] }.map do |signal, group|
        { signal:, label: group.first[:label], accepted_us: group.sum { |row| row[:accepted_us] }, row_count: group.length }
      end
      { from: @from, to: @to, generated_at: @generated_at, by_signal: totals, rows: }
    end

    protected

    def gain_rows
      connection = ::VpsEvidenceInterval.connection
      sql = ::VpsEvidenceInterval.live.where(signal: ::VpsEvidence::SIGNALS.keys)
                                 .where('accepted_at > ? AND accepted_at <= ?', @from, @to)
                                 .joins('LEFT JOIN vpses evidence_vps ON evidence_vps.id = vps_evidence_intervals.vps_id')
                                 .joins('LEFT JOIN users evidence_user ON evidence_user.id = vps_evidence_intervals.user_id')
                                 .group('vps_evidence_intervals.signal, vps_evidence_intervals.vps_id, vps_evidence_intervals.user_id, vps_evidence_intervals.accounting_since')
                                 .having('SUM(credit_us) > 0')
                                 .select('vps_evidence_intervals.signal, vps_evidence_intervals.vps_id, vps_evidence_intervals.user_id, vps_evidence_intervals.accounting_since',
                                         'SUM(credit_us) AS accepted_us, MIN(accepted_at) AS first_accepted_at, MAX(accepted_at) AS last_accepted_at',
                                         'MAX(evidence_vps.id) AS current_vps_id, MAX(evidence_vps.hostname) AS hostname, MAX(evidence_user.login) AS user_login')
                                 .order(Arel.sql('BINARY vps_evidence_intervals.signal ASC, accepted_us DESC, vps_evidence_intervals.vps_id ASC, vps_evidence_intervals.user_id ASC, vps_evidence_intervals.accounting_since ASC')).to_sql
      connection.select_all(sql).map do |row|
        signal = row.fetch('signal')
        { signal:, label: ::VpsEvidence.definition(signal)::LABELS.fetch(@language, ::VpsEvidence.definition(signal)::LABELS.fetch('en')),
          vps_id: row.fetch('vps_id').to_i, user_id: row.fetch('user_id').to_i, accounting_since: time(row['accounting_since']),
          hostname: row['hostname'], user_login: row['user_login'], accepted_us: row.fetch('accepted_us').to_i,
          first_accepted_at: time(row.fetch('first_accepted_at')), last_accepted_at: time(row.fetch('last_accepted_at')),
          vps_url: row['current_vps_id'] && @base && "#{@base}?#{URI.encode_www_form(page: 'adminvps', action: 'info', veid: row.fetch('vps_id'))}" }
      end
    end

    def time(value)
      return if value.nil?

      value.is_a?(String) ? Time.parse("#{value} UTC").utc : value.to_time.utc
    end

    def safe_base_url(value)
      uri = URI.parse(value.to_s)
      return unless %w[http https].include?(uri.scheme) && uri.host && !uri.userinfo && !uri.query && !uri.fragment

      "#{uri.to_s.sub(%r{/+\z}, '')}/"
    rescue URI::InvalidURIError
      nil
    end
  end
end
