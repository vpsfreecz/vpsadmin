require 'digest'
require 'json'

module VpsAdmin::API
  # Validate original event facts before acquiring database locks. Source
  # qualification remains the node's predicate; rounded percentages are context.
  class VpsEvidencePayload
    MAX_INTEGER = (2**63) - 1
    HEADER_KEYS = %w[schema signal representation kind producer_epoch boot_id observer_epoch sequence batch_id part parts observed_at_us observed_mono_us sample_epoch sample_sequence interval_us coverage_started_mono_us coverage_valid gap_since_previous gap_reason targets_complete roster_complete signal_context targets segments].freeze
    TARGET_KEYS = %w[pool id run qualification previous_qualification linked window_from_mono_us window_to_mono_us reason qualification_evidence].freeze
    SEGMENT_KEYS = %w[target from_mono_us to_mono_us from_at_us to_at_us credit_us measurement peak_unit peak_value peak_is_lower_bound evidence].freeze
    QUALIFICATIONS = %w[qualified ineligible unknown].freeze

    attr_reader :data, :digest, :definition

    def initialize(data, now:, config:)
      @data = data
      check(data.is_a?(Hash))
      check(JSON.generate(data).bytesize <= 16_384)
      tree!(data)
      keys!(data, HEADER_KEYS)
      check(data['schema'] == 1 && %w[sample heartbeat].include?(data['kind']))
      @definition = ::VpsEvidence.definition(data['signal'])
      check(data['representation'] == definition::REPRESENTATION)
      check(data['producer_epoch'].is_a?(String) && data['producer_epoch'].match?(/\A[0-9a-f]{32}\z/))
      check(data['boot_id'].is_a?(String) && data['boot_id'].match?(/\A[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\z/))
      %w[observer_epoch sample_epoch].each { |key| ascii!(data[key], 95) }
      %w[sequence sample_sequence interval_us].each { |key| integer!(data[key], positive: true) }
      check(data['batch_id'] == "#{data['signal']}:#{data['producer_epoch']}:#{data['sequence']}")
      check(data['parts'].is_a?(Integer) && data['parts'].between?(1, 64))
      check(data['part'].is_a?(Integer) && data['part'].between?(1, data['parts']))
      %w[observed_at_us observed_mono_us].each { |key| integer!(data[key]) }
      integer!(data['coverage_started_mono_us']) unless data['coverage_started_mono_us'].nil?
      check(data['coverage_started_mono_us'].nil? || data['coverage_started_mono_us'] <= data['observed_mono_us'])
      %w[coverage_valid gap_since_previous targets_complete roster_complete].each { |key| boolean!(data[key]) }
      check(data['gap_since_previous'] == !data['gap_reason'].nil?)
      check(!data['coverage_valid'] || !data['coverage_started_mono_us'].nil?)
      validate_time!(now:, config:)
      definition.validate_context!(self)
      check(data['targets'].is_a?(Array) && data['targets'].size <= 16)
      check(data['segments'].is_a?(Array) && data['segments'].size <= 16)
      data['targets'].each { |target| target!(target) }
      check(data['targets'].map { |t| [t['pool'], t['id']] }.uniq.size == data['targets'].size)
      data['segments'].each { |segment| segment!(segment) }
      data['segments'].group_by { |s| s['target'] }.each_value do |segments|
        ordered = segments.sort_by { |s| s['from_mono_us'] }
        check(ordered.each_cons(2).all? { |a, b| a['to_mono_us'] <= b['from_mono_us'] })
        check(ordered.sum { |s| s['credit_us'] } <= data['interval_us'])
      end
      check(data['kind'] != 'heartbeat' || data['segments'].empty?)
      @digest = Digest::SHA256.hexdigest(JSON.generate(sorted(data)))
    end

    # Intake validation cannot extend observation lifetime through a lock wait.
    def validate_time!(now:, config:)
      age = (now.to_r * 1_000_000).to_i - data['observed_at_us']
      check(age.between?(-2_000_000, config.fetch(:freshness_seconds) * 1_000_000))
      check(data['interval_us'] < (config.fetch(:freshness_seconds) - 5) * 1_000_000)
    end

    def header
      data.except('part', 'targets', 'segments')
    end

    def observed_at
      self.class.time(data.fetch('observed_at_us'))
    end

    def self.time(microseconds)
      Time.at(Rational(microseconds, 1_000_000)).utc
    end

    def check(value)
      raise ::VpsEvidence::InvalidEvent, 'Invalid VPS evidence event' unless value
    end

    def keys!(value, keys)
      check(value.is_a?(Hash) && value.keys.sort == keys.sort)
    end

    def integer!(value, positive: false)
      check(value.is_a?(Integer) && value.between?(positive ? 1 : 0, MAX_INTEGER))
    end

    def boolean!(value)
      check([true, false].include?(value))
    end

    def string!(value, maximum)
      check(value.is_a?(String) && value.valid_encoding? && value.bytesize.between?(1, maximum) && !value.match?(/[[:cntrl:]]/))
    end

    def ascii!(value, maximum)
      string!(value, maximum)
      check(value.ascii_only?)
    end

    def tree!(value, depth = 0)
      check(depth <= 12)
      case value
      when Hash
        value.each do |key, item|
          check(key.is_a?(String))
          tree!(item, depth + 1)
        end
      when Array
        value.each { |item| tree!(item, depth + 1) }
      else
        check(value.nil? || value == true || value == false || value.is_a?(Integer) || value.is_a?(String))
      end
    end

    def target!(target)
      keys!(target, TARGET_KEYS)
      %w[pool id].each { |key| string!(target[key], 255) }
      check(QUALIFICATIONS.include?(target['qualification']) && QUALIFICATIONS.include?(target['previous_qualification']))
      boolean!(target['linked'])
      if target['run'].nil?
        check(target['qualification'] == 'unknown')
      else
        keys!(target['run'], %w[group_path init_pid init_start_time_ticks])
        string!(target['run']['group_path'], 1024)
        components = target['run']['group_path'].split('/').reject(&:empty?)
        check(!components.empty? && !components.intersect?(%w[. ..]))
        %w[init_pid init_start_time_ticks].each { |key| integer!(target['run'][key], positive: true) }
      end
      first, last = target.values_at('window_from_mono_us', 'window_to_mono_us')
      if first.nil? || last.nil?
        check(first.nil? && last.nil? && !target['linked'])
      else
        integer!(first)
        integer!(last)
        check(first < last && last <= data['observed_mono_us'])
      end
      definition.validate_target!(self, target)
    end

    def segment!(segment)
      keys!(segment, SEGMENT_KEYS)
      integer!(segment['target'])
      target = data['targets'][segment['target']]
      check(target)
      %w[from_mono_us to_mono_us from_at_us to_at_us credit_us].each { |key| integer!(segment[key]) }
      first, last = segment.values_at('from_mono_us', 'to_mono_us')
      check(first < last && segment['credit_us'] == last - first && segment['credit_us'] <= data['interval_us'])
      %w[from to].each do |key|
        check(segment["#{key}_at_us"] == data['observed_at_us'] + segment["#{key}_mono_us"] - data['observed_mono_us'])
      end
      peak = segment.values_at('measurement', 'peak_unit', 'peak_value', 'peak_is_lower_bound')
      check(peak.all?(&:nil?) || peak.none?(&:nil?))
      unless peak.all?(&:nil?)
        ascii!(segment['measurement'], 64)
        ascii!(segment['peak_unit'], 32)
        integer!(segment['peak_value'])
        boolean!(segment['peak_is_lower_bound'])
      end
      definition.validate_segment!(self, segment, target)
    end

    def condition
      definition.condition(data)
    end

    def eligible?(target)
      definition.eligible?(data, target)
    end

    def intervals_for(index)
      data['segments'].select { |segment| segment['target'] == index }.map do |segment|
        { from_at: self.class.time(segment.fetch('from_at_us')), to_at: self.class.time(segment.fetch('to_at_us')),
          credit_us: segment.fetch('credit_us'), **segment.slice('measurement', 'peak_unit', 'peak_value', 'peak_is_lower_bound').symbolize_keys,
          evidence: { 'segment' => segment, 'target' => data['targets'][index], 'source' => data.except('targets', 'segments') } }
      end
    end

    def sorted(value)
      case value
      when Hash then value.keys.sort.to_h { |key| [key, sorted(value[key])] }
      when Array then value.map { |item| sorted(item) }
      else value
      end
    end
  end
end
