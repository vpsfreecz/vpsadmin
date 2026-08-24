require 'json'

module NodeCtld
  class Commands::Vps::RecoverCleanup < Commands::Base
    CONTINUABLE_OUTCOMES = %w[cleaned quarantined partial legacy_unknown].freeze
    CLEANUP_RESULT_KEYS = %i[
      outcome
      incarnation_id
      run_id
      lifecycle_revision
      requested_cleanup
      completed_cleanup
      active_slot_released
      residual_run_ids
      evidence
      hazards
    ].freeze
    CLEANUP_EVIDENCE_KEYS = %i[
      observed_at
      requested
      runtime_state
      runtime_state_source
    ].freeze

    handle 3303
    needs :system, :osctl

    def exec
      cleanup = {}
      cleanup[:cgroups] = true if @cgroups
      cleanup[:network_interfaces] = true if @network_interfaces

      requested_cleanup = cleanup.filter_map do |name, enabled|
        next unless enabled

        name == :network_interfaces ? 'netifs' : name.to_s
      end
      requested_cleanup = %w[cgroups netifs] if requested_cleanup.empty?

      result = osctl(%i[ct recover cleanup], @vps_id, cleanup)
      recovery = parse_recovery_output(
        result.output,
        requested_cleanup:
      )
      outcome = recovery.fetch(:outcome)

      unless CONTINUABLE_OUTCOMES.include?(outcome)
        raise "unsupported recovery cleanup outcome #{outcome.inspect}"
      end

      output[:recovery_cleanup] = recovery

      if outcome == 'cleaned'
        ok
      else
        output[:warnings] = recovery.fetch(:hazards)
        { ret: :warning }
      end
    end

    def rollback
      ok
    end

    protected

    def parse_recovery_output(raw_output, requested_cleanup:)
      parsed = parse_json_output(raw_output)

      parsed = parsed[:output] if parsed.is_a?(Hash) && parsed[:output].is_a?(Hash)

      if parsed.is_a?(Hash) && parsed[:outcome]
        normalized = normalize_cleanup_evidence(parsed)
        recovery = normalized.merge(
          outcome: parsed[:outcome].to_s,
          hazards: Array(parsed[:hazards])
        )

        if recovery[:outcome] == 'cleaned' &&
           !complete_cleaned_evidence?(normalized, requested_cleanup)
          return legacy_unknown(
            'the node returned incomplete structured cleanup evidence; ' \
            'cleanup result is unknown',
            reported_cleanup: parsed
          )
        end

        recovery
      else
        legacy_unknown(
          'the node returned no structured cleanup evidence; cleanup result is unknown'
        )
      end
    end

    def complete_cleaned_evidence?(recovery, requested_cleanup)
      return false unless CLEANUP_RESULT_KEYS.all? { |key| recovery.has_key?(key) }
      return false unless recovery[:incarnation_id].is_a?(String) &&
                          !recovery[:incarnation_id].empty?
      return false unless recovery[:run_id].nil? ||
                          (recovery[:run_id].is_a?(String) &&
                           !recovery[:run_id].empty?)
      return false unless recovery[:lifecycle_revision].is_a?(Integer) &&
                          recovery[:lifecycle_revision] >= 0
      return false unless boolean?(recovery[:active_slot_released])
      return false unless string_array?(recovery[:requested_cleanup])
      return false unless string_array?(recovery[:completed_cleanup])
      return false unless string_array?(recovery[:residual_run_ids])
      return false unless recovery[:hazards].is_a?(Array) &&
                          recovery[:hazards].empty?
      return false unless recovery[:evidence].is_a?(Hash)
      return false unless CLEANUP_EVIDENCE_KEYS.all? do |key|
        recovery[:evidence].has_key?(key)
      end
      return false unless recovery[:evidence][:observed_at].is_a?(Numeric)
      return false unless nonempty_string?(recovery[:evidence][:runtime_state])
      return false unless nonempty_string?(
        recovery[:evidence][:runtime_state_source]
      )

      same_string_set?(recovery[:requested_cleanup], requested_cleanup) &&
        same_string_set?(recovery[:completed_cleanup], requested_cleanup) &&
        same_string_set?(recovery[:evidence][:requested], requested_cleanup)
    end

    def boolean?(value)
      [true, false].include?(value)
    end

    def normalize_cleanup_evidence(recovery)
      evidence = recovery[:evidence]
      return recovery unless evidence.is_a?(Hash)

      normalized = evidence.dup
      {
        runtime_state: :lxc_state,
        runtime_state_source: :lxc_state_source
      }.each do |current, legacy|
        next if normalized.has_key?(current)
        next unless normalized.has_key?(legacy)

        normalized[current] = normalized[legacy]
      end
      normalized.delete(:lxc_state)
      normalized.delete(:lxc_state_source)

      recovery.merge(evidence: normalized)
    end

    def string_array?(value)
      value.is_a?(Array) && value.all? { |item| nonempty_string?(item) }
    end

    def same_string_set?(value, expected)
      string_array?(value) &&
        value.uniq.length == value.length &&
        value.sort == expected.sort
    end

    def nonempty_string?(value)
      value.is_a?(String) && !value.empty?
    end

    def legacy_unknown(message, reported_cleanup: nil)
      ret = {
        outcome: 'legacy_unknown',
        hazards: [message]
      }
      ret[:reported_cleanup] = reported_cleanup if reported_cleanup
      ret
    end

    def parse_json_output(raw_output)
      raw = raw_output.to_s.strip
      return if raw.empty? || raw == 'null'

      candidates = [raw]
      candidates.concat(raw.lines.reverse_each.map(&:strip))

      candidates.uniq.each do |candidate|
        next if candidate.empty? || candidate == 'null'

        begin
          return JSON.parse(candidate, symbolize_names: true)
        rescue JSON::ParserError
          next
        end
      end

      nil
    end
  end
end
