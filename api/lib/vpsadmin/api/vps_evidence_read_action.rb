module VpsAdmin::API
  module VpsEvidenceReadResource
    def self.included(resource)
      resource.singular true
      resource.params(:all) do
        string :id, label: 'VPS and signal ID', desc: 'Stable identifier for the VPS and supported signal pair.'
        resource VpsAdmin::API::Resources::VPS, value_label: :hostname
        resource VpsAdmin::API::Resources::User, value_label: :login
        resource VpsAdmin::API::Resources::Node, value_label: :domain_name, nullable: true
        string :hostname, label: 'Current hostname', desc: 'Current VPS hostname, independent of names saved with incidents.'
        string :signal, label: 'Evidence signal', desc: 'Supported signal identifier; currently rtnl_latency.'
        string :label, label: 'Signal name', desc: 'Signal name in the response language.'
        string :representation, label: 'Evidence representation', desc: 'Accounting representation; currently qualified_duration.'
        bool :configuration_valid, label: 'Valid evidence configuration', desc: 'Whether the effective settings for this signal are valid. Missing or stale observations do not make configuration invalid.'
        integer :credit_us, nullable: true, label: 'Current credited microseconds', desc: 'Recorded duration in integer microseconds, clipped to the current occurrence window. Null means unavailable. Zero means no recorded credit, without establishing collection or VPS health.'
        datetime :window_from, nullable: true, label: 'Current window start', desc: 'Excluded lower occurrence-time boundary in UTC with microseconds; null when configuration is invalid.'
        datetime :window_to, nullable: true, label: 'Current window end', desc: 'Included upper occurrence-time boundary in UTC with microseconds, equal to read_at; null when configuration is invalid.'
        integer :window_seconds, nullable: true, label: 'Current window in seconds', desc: 'Effective rolling window length in seconds; null when configuration is invalid.'
        integer :threshold_seconds, nullable: true, label: 'Current reporting threshold in seconds', desc: 'Effective credited-duration threshold for creating an incident, in seconds; null when configuration is invalid.'
        integer :repeat_seconds, nullable: true, label: 'Current repeat period in seconds', desc: 'Effective minimum time between accepted incidents, in seconds; null when configuration is invalid.'
        bool :reporting_enabled, nullable: true, label: 'Incident reporting enabled', desc: 'Current reporting switch, independent of recorded credit; null when configuration is invalid.'
        datetime :last_incident_at, nullable: true, label: 'Last evidence incident', desc: 'Last accepted incident time for this signal and owner accounting period. Null without history or when ownership cannot be matched.'
        datetime :last_observed_at, nullable: true, label: 'Last source observation', desc: 'Last stored source observation time for the matching owner accounting period, even if stale. Null without history or when ownership cannot be matched.'
        float :observation_age_seconds, nullable: true, label: 'Observation age in seconds', desc: 'Age of the last source observation at read_at, in seconds; null when no observation is available.'
        string :observation_state, choices: %w[no_data fresh stale], label: 'Observation freshness', desc: 'Freshness of the available observation, separate from qualification and reporting eligibility. With invalid settings, freshness uses the signal default.'
        string :qualification, nullable: true, choices: %w[qualified ineligible unknown], label: 'Last source qualification', desc: 'Last stored source assessment, which can remain visible after it becomes stale. Null without history or when ownership cannot be matched.'
        bool :report_eligible, nullable: true, label: 'Current observations meet reporting criteria', desc: 'Whether fresh source proof, current placement and VPS status permit reporting, independently of enablement, credit threshold and repeat period. Null when configuration is invalid.'
        bool :report_due, nullable: true, label: 'Evidence incident is due', desc: 'Whether reporting is enabled, current proof is eligible, credit reaches the threshold and the repeat period has elapsed. Reading this value creates no incident. Null when configuration is invalid.'
        bool :window_complete, nullable: true, label: 'Complete window coverage', desc: 'Whether recorded coverage spans the current window and the observation is recent. This does not establish reporting eligibility. Null when configuration is invalid.'
        string :measurement, nullable: true, label: 'Observed measurement', desc: 'Measurement identifier for the peak across contributing intervals; null without a compatible peak.'
        string :peak_unit, nullable: true, label: 'Observed peak unit', desc: 'Unit of peak_value; null without a compatible peak.'
        integer :peak_value, nullable: true, label: 'Observed peak', desc: 'Integer peak in peak_unit across contributing intervals; null without a compatible measurement.'
        bool :peak_is_lower_bound, nullable: true, label: 'Observed peak is a lower bound', desc: 'Whether the peak is a lower bound because a contributing observation was still pending; null without a compatible peak.'
        string :condition_measurement, nullable: true, label: 'Condition measurement', desc: 'Measurement identifier in the fixed signal condition; null when no condition is defined.'
        string :condition_operator, nullable: true, label: 'Condition operator', desc: 'Comparison operator in the fixed signal condition; null when no condition is defined.'
        integer :condition_value, nullable: true, label: 'Condition value', desc: 'Integer value in condition_unit for the fixed signal condition, independent of duration and incident-count thresholds; null when no condition is defined.'
        string :condition_unit, nullable: true, label: 'Condition unit', desc: 'Unit of condition_value; null when no condition is defined.'
      end
    end
  end

  module VpsEvidenceReadAction
    def self.included(action)
      action.http_method :get
      action.route ''
      action.meta(:global) do
        output do
          datetime :read_at, label: 'Evidence read at', desc: 'Single UTC instant used for this response and its occurrence window, with microsecond precision.'
          bool :configuration_valid, label: 'Selected signal configurations are valid', desc: 'Whether all selected signals have valid effective settings; independent of observation availability.'
          custom :unavailable_signals, label: 'Signals with invalid configuration', desc: 'Sorted JSON string array without duplicates, containing only selected supported signals with invalid effective settings. Bounded by the supported signal list; [] when all selected settings are valid. Missing or stale observations are separate.'
        end
      end
      action.authorize do |user|
        output blacklist: %i[user node] unless user.role == :admin
        allow
      end
    end

    def read_projection
      @read_projection ||= ::VpsEvidenceReadProjection.new(user: current_user, language: ::I18n.locale)
    end

    def evidence_result(result)
      set_meta(result[:meta].transform_values { |value| value.is_a?(Time) ? value.iso8601(6) : value })
      result[:rows].map do |row|
        result_row = row.except(:vps_id, :user_id, :user_login, :node_id, :node_name)
        ::VpsEvidenceReadProjection::DATE_FIELDS.each { |key| result_row[key] = row[key]&.iso8601(6) }
        result_row.merge(vps: evidence_reference(row[:vps_id], :hostname, row[:hostname]),
                         user: evidence_reference(row[:user_id], :login, row[:user_login]),
                         node: evidence_reference(row[:node_id], :domain_name, row[:node_name]))
      end
    end

    def evidence_reference(id, label, value)
      id && { id:, label => value, _meta: { path_params: [id], resolved: false } }
    end
  end
end
