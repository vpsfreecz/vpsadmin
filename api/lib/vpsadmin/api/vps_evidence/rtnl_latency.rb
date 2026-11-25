module VpsAdmin::API
  module Evidence
    # Signal semantics stay here; the shared duration ledger consumes validated
    # intervals, eligibility and a typed reporting condition only.
    class RtnlLatency
      SIGNAL = 'rtnl_latency'.freeze
      REPRESENTATION = 'qualified_duration'.freeze
      CATEGORY = 'vps_evidence_rtnl_latency'.freeze
      LABELS = { 'en' => 'RTNL latency', 'cs' => 'Latence RTNL' }.freeze
      DEFAULTS = { enabled: false, window_seconds: 86_400, threshold_seconds: 300, repeat_seconds: 86_400, freshness_seconds: 30 }.freeze
      REASONS = %w[initial_baseline run_changed resource_unknown rank_unknown ineligible vanished unlinked oversize].freeze
      GAPS = %w[startup sample_gap cache_gap coverage_lost pressure clock_change oversize].freeze
      CUTOFF_US = 1_000_000
      CONDITION = { 'measurement' => SIGNAL, 'operator' => 'gt', 'value' => CUTOFF_US, 'unit' => 'microseconds' }.freeze

      def self.validate_context!(payload)
        payload.check(payload.data['gap_reason'].nil? || GAPS.include?(payload.data['gap_reason']))
        context = payload.data['signal_context']
        payload.keys!(context, %w[cutoff_us policy])
        payload.check(context['cutoff_us'] == CUTOFF_US)
        payload.keys!(context['policy'], %w[cpu_percent_milli memory_percent_milli load_top])
        context['policy'].each_value { |value| payload.integer!(value, positive: true) }
      end

      def self.validate_target!(payload, target)
        payload.check(target['reason'].nil? || REASONS.include?(target['reason']))
        facts = target['qualification_evidence']
        payload.keys!(facts, %w[cpu_percent_milli memory_percent_milli cpu_limit_state memory_limit_state rank])
        %w[cpu memory].each do |resource|
          payload.check(%w[limited unlimited unknown].include?(facts["#{resource}_limit_state"]))
          value = facts["#{resource}_percent_milli"]
          payload.integer!(value) unless value.nil?
        end
        payload.integer!(facts['rank'], positive: true) unless facts['rank'].nil?
        return unless target['qualification'] == 'qualified'

        payload.check(target['run'] && (facts['rank'].nil? || facts['rank'] <= payload.data['signal_context']['policy']['load_top']))
        %w[cpu memory].each do |resource|
          payload.check(facts["#{resource}_limit_state"] != 'unknown')
          payload.check(facts["#{resource}_limit_state"] != 'limited' || !facts["#{resource}_percent_milli"].nil?)
        end
      end

      def self.validate_segment!(payload, segment, target)
        data = payload.data
        payload.check(target['qualification'] == 'qualified' && target['previous_qualification'] == 'qualified' && target['linked'])
        evidence = segment['evidence']
        payload.keys!(evidence, %w[probe probe_started_mono_us probe_completed_mono_us coverage_started_mono_us])
        %w[probe probe_started_mono_us coverage_started_mono_us].each { |key| payload.integer!(evidence[key], positive: key == 'probe') }
        completed = evidence['probe_completed_mono_us']
        payload.integer!(completed) unless completed.nil?
        first, last = segment.values_at('from_mono_us', 'to_mono_us')
        finish = completed || data['observed_mono_us']
        payload.check(data['coverage_valid'] && data['coverage_started_mono_us'])
        payload.check(first >= evidence['probe_started_mono_us'] + CUTOFF_US)
        payload.check(first >= [target['window_from_mono_us'], data['observed_mono_us'] - data['interval_us'], evidence['coverage_started_mono_us'], data['coverage_started_mono_us']].max)
        payload.check(last <= [target['window_to_mono_us'], finish, data['observed_mono_us']].min)
        payload.check(segment['measurement'] == SIGNAL && segment['peak_unit'] == 'microseconds')
        payload.check(segment['peak_value'] == finish - evidence['probe_started_mono_us'])
        payload.check(segment['peak_is_lower_bound'] == completed.nil?)
      end

      def self.condition(data)
        { 'measurement' => SIGNAL, 'operator' => 'gt', 'value' => data['signal_context']['cutoff_us'], 'unit' => 'microseconds' }
      end

      def self.eligible?(data, target)
        target['qualification'] == 'qualified' && target['linked'] && target['run'] && data['coverage_valid']
      end

      def self.message(vps:, user:, snapshot:, intervals:)
        VpsAdmin::API::IncidentReports.rtnl_event_message(vps:, user:, snapshot:, intervals:)
      end
    end
  end
end
