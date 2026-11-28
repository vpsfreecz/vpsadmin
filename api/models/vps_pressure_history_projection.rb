require 'time'

class VpsPressureHistoryProjection
  SIGNAL = 'rtnl_latency'.freeze

  def initialize(user:, now: Time.now.utc)
    @user = user
    @read_at = now.utc
  end

  def for_vps(id, days: 7)
    raise ArgumentError, 'Invalid history period' unless days.is_a?(Integer) && [7, 30].include?(days)

    today = Time.utc(@read_at.year, @read_at.month, @read_at.day)
    first = today - ((days - 1) * 86_400)
    last = today + 86_400
    retained_from = today - (31 * 86_400)
    epoch_key = "COALESCE(DATE_FORMAT(v.incident_accounting_since, '%Y-%m-%dT%H:%i:%s.%fZ'), '-')"
    filters = ["v.id = #{q(id)}", "v.object_state IN (#{%i[active suspended soft_delete].map { |state| q(Vps.object_states[state]) }.join(',')})"]
    filters << "v.user_id = #{q(@user.id)}" unless @user.role == :admin
    # One statement captures authorization, mutable epoch/transfer state and
    # retained daily totals together. An absent state is not missing history.
    raw = Vps.connection.select_all(<<~SQL).to_a
      SELECT v.incident_accounting_since AS accounting_since,
        v.incident_owner_transfer_chain_id IS NOT NULL AS transfer_pending,
        s.id IS NOT NULL AND (s.user_id <> v.user_id OR NOT (s.accounting_since <=> v.incident_accounting_since)) AS state_mismatch,
        d.day, d.recorded_us,
        (SELECT MIN(f.first_accepted_at) FROM vps_evidence_daily_totals f
          WHERE f.vps_id = v.id AND f.signal = #{q(SIGNAL)} AND f.user_id = v.user_id
            AND f.accounting_epoch_key = #{epoch_key} AND f.accounting_since <=> v.incident_accounting_since AND f.recorded_us > 0
            AND f.day >= #{q(retained_from.to_date)} AND f.day < #{q(last.to_date)}) AS first_recorded_at
      FROM vpses v
      LEFT JOIN vps_evidence_states s ON s.vps_id = v.id AND s.signal = #{q(SIGNAL)}
      LEFT JOIN vps_evidence_daily_totals d ON d.vps_id = v.id AND d.signal = #{q(SIGNAL)} AND d.user_id = v.user_id
        AND d.accounting_epoch_key = #{epoch_key} AND d.accounting_since <=> v.incident_accounting_since
        AND d.day >= #{q(first.to_date)} AND d.day < #{q(last.to_date)} AND d.recorded_us > 0
      WHERE #{filters.join(' AND ')} ORDER BY d.day
    SQL
    raise ActiveRecord::RecordNotFound if raw.empty?

    available = !boolean(raw.first['transfer_pending']) && !boolean(raw.first['state_mismatch'])
    epoch = time(raw.first['accounting_since'])
    totals = available ? raw.filter_map { |row| [row['day'].to_s, row['recorded_us'].to_i] if row['day'] }.to_h : {}
    rows = days.times.map do |index|
      from = first + (index * 86_400)
      { id: from.to_date.iso8601, from_at: from, to_at: from + 86_400,
        recorded_us: totals[from.to_date.iso8601], partial_day: from == today }
    end
    values = rows.filter_map { |row| row[:recorded_us] }
    { rows:, meta: { read_at: @read_at, timezone: 'UTC', range_from: first, range_to: last,
                     total_recorded_us: values.empty? ? nil : values.sum,
                     first_recorded_at: available ? time(raw.first['first_recorded_at']) : nil,
                     accounting_since: epoch, ownership_limited: !epoch.nil? && epoch > first, available: } }
  end

  protected

  def q(value) = Vps.connection.quote(value)

  def boolean(value) = [true, 1, '1'].include?(value)

  def time(value)
    return if value.nil?

    value.is_a?(String) ? Time.parse("#{value} UTC").utc : value.to_time.utc
  end
end
