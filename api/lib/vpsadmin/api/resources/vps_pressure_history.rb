class VpsAdmin::API::Resources::VpsPressureHistory < HaveAPI::Resource
  singular true
  route 'vps_pressure_history'
  desc 'Read daily recorded memory pressure time for the current VPS ownership period'

  class Index < HaveAPI::Action
    http_method :get
    route ''
    desc 'Read the last 7 or 30 UTC calendar days, including today'

    input do
      resource VpsAdmin::API::Resources::VPS, required: true, value_label: :hostname
      integer :days, default: 7, fill: true, choices: [7, 30], label: 'Calendar days'
    end
    output(:object_list, namespace: :vps_pressure_history) do
      string :id, label: 'UTC date'
      datetime :from_at, label: 'Day start', desc: 'Included UTC midnight boundary.'
      datetime :to_at, label: 'Day end', desc: 'Excluded next UTC midnight, including for today.'
      integer :recorded_us, nullable: true, label: 'Recorded microseconds', desc: 'Positive total duration of accepted contributions occurring in this UTC day and current accounting period; null if no contribution was recorded or history is unavailable.'
      bool :partial_day, label: 'Partial day', desc: 'True only for today. False does not establish complete observations.'
    end
    meta(:global) do
      output do
        datetime :read_at, label: 'Read at', desc: 'UTC instant of the consistent read, not a clipping boundary for daily totals.'
        string :timezone, choices: ['UTC'], label: 'History timezone'
        datetime :range_from, label: 'Range start', desc: 'Included UTC midnight at the start of the first returned day.'
        datetime :range_to, label: 'Range end', desc: 'Excluded UTC midnight following today.'
        integer :total_recorded_us, nullable: true, label: 'Total recorded microseconds', desc: 'Exact sum of returned positive daily totals; null if none or unavailable.'
        datetime :first_recorded_at, nullable: true, label: 'First retained recording', desc: 'Earliest first-acceptance timestamp among positive rows in the retained 32 UTC days for this VPS, signal and current ownership epoch. Not first occurrence, first-ever recording or coverage; can move after pruning.'
        datetime :accounting_since, nullable: true, label: 'Current accounting period start', desc: 'Actual start of the VPS\'s current accounting period; null when unknown.'
        bool :ownership_limited, label: 'History limited by ownership', desc: 'True when accounting_since is set and is later than range_from.'
        bool :available, label: 'History available', desc: 'False for pending ownership transfer or a known state/epoch mismatch. True can still have no recorded contributions.'
      end
    end
    authorize { allow }

    def exec
      result = ::VpsPressureHistoryProjection.new(user: current_user).for_vps(input[:vps].id, days: input[:days])
      set_meta(result[:meta].transform_values { |value| value.is_a?(Time) ? value.iso8601(6) : value })
      result[:rows].map { |row| row.merge(from_at: row[:from_at].iso8601(6), to_at: row[:to_at].iso8601(6)) }
    rescue ArgumentError => e
      error!(e.message)
    end
  end
end
