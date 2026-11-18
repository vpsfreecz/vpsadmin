require 'digest'

# Trusted site declarations are loaded once. Selectors receive captured values
# only, and are called exclusively by ordinary report creation.
class IncidentEscalation
  class InvalidConfiguration < StandardError; end

  MODES = %w[observe notify enforce].freeze
  Context = Struct.new(
    :now, :report, :source, :vps, :owner, :accounting_since, :policy_key, :count_7d, :count_30d,
    :last_warning_at, :last_stop_at, :global_mode, :global_overrides,
    :vps_overrides, :stop_exempt
  )

  Rule = Struct.new(:key, :labels, :descriptions, :category, :warning_limit, :stop_limit,
                    :suppressed, :warning_template, :stopped_template, :selector) do
    def reports(scope = IncidentReport.all)
      scope.where(id: IncidentPolicyEvaluation.where(policy_key: key, matched: true).select(:incident_report_id))
    end

    def label(language = :en)
      labels.fetch(language.to_s, labels.fetch('en'))
    end

    def description(language = :en)
      descriptions[language.to_s] || descriptions['en']
    end

    def metadata
      { 'key' => key, 'labels' => labels, 'descriptions' => descriptions,
        'warning_template' => warning_template.to_s, 'stopped_template' => stopped_template.to_s }
    end

    def base
      { 'warning_limit' => warning_limit, 'stop_limit' => stop_limit, 'mode' => 'enforce',
        'suppress_actions' => suppressed }
    end
  end

  class RuleBuilder
    def initialize(key)
      @key = key.to_s
      # Categories follow the existing SystemConfig identifier contract.
      unless @key.match?(/\A[a-zA-Z0-9_]{1,59}\z/)
        raise InvalidConfiguration, 'Invalid incident policy key'
      end

      @descriptions = {}
      @suppressed = false
      @warning = :vps_incident_warning
      @stopped = :vps_incident_stopped
    end

    def labels(**values)
      @labels = values.transform_keys(&:to_s)
    end

    def descriptions(**values)
      @descriptions = values.transform_keys(&:to_s)
    end

    def limits(warning:, stop:)
      @warning_limit = warning
      @stop_limit = stop
    end

    def applies_if(&block)
      raise InvalidConfiguration, 'Missing incident selector' unless block

      @selector = block
    end

    def suppress_actions(value)
      @suppressed = value
    end

    def templates(warning:, stopped:)
      @warning = warning
      @stopped = stopped
    end

    def build
      unless @labels.is_a?(Hash) && @labels['en'].is_a?(String) &&
             @labels.values.all? { |v| v.is_a?(String) && v.length.between?(1, 160) } &&
             @descriptions.values.all? { |v| v.is_a?(String) && v.length.between?(1, 1000) } &&
             [@warning_limit, @stop_limit].all? { |v| v.is_a?(Integer) && v.between?(1, 2_147_483_647) } &&
             @stop_limit >= @warning_limit && [true, false].include?(@suppressed) &&
             [@warning, @stopped].all? { |v| v.is_a?(Symbol) && v.to_s.match?(/\A[a-z][a-z0-9_]{0,99}\z/) }
        raise InvalidConfiguration, 'Invalid incident policy declaration'
      end

      Rule.new(key: @key.freeze, labels: IncidentEscalation.freeze_values(@labels),
               descriptions: IncidentEscalation.freeze_values(@descriptions), category: "incident_policy_#{@key}".freeze,
               warning_limit: @warning_limit, stop_limit: @stop_limit,
               suppressed: @suppressed, warning_template: @warning, stopped_template: @stopped, selector: @selector).freeze
    end
  end

  class Configuration
    attr_reader :rules

    def initialize
      @rules = {}
    end

    def rule(key, &)
      raise InvalidConfiguration, 'Duplicate incident policy' if @rules.keys.any? { |existing| existing.casecmp?(key.to_s) }

      builder = RuleBuilder.new(key)
      builder.instance_eval(&)
      @rules[key.to_s] = builder.build
    end
  end

  def self.configure(&)
    raise InvalidConfiguration, 'Incident policy is already initialized' if @configured || @finalized

    declaration = Configuration.new
    declaration.instance_eval(&)
    remove_const(:RULES)
    const_set(:RULES, declaration.rules.sort.to_h.freeze)
    @configured = true
  end

  def self.finalize!
    path = File.join(VpsAdmin::API.root, 'config', 'incident_escalation.rb')
    if File.exist?(path) && !@configured
      raise InvalidConfiguration, 'Incident policy file did not configure policies'
    end

    @site_policy = File.exist?(path)
    @policy_digest = @site_policy ? Digest::SHA256.file(path).hexdigest : Digest::SHA256.hexdigest('empty-incident-policy-v3')
    @finalized = true
  end

  def self.site_policy?
    @site_policy == true
  end

  class << self
    attr_reader :policy_digest
  end

  def self.freeze_values(value)
    case value
    when Hash
      value.to_h { |key, item| [freeze_values(key), freeze_values(item)] }.freeze
    when Array
      value.map { |item| freeze_values(item) }.freeze
    else
      value.dup.freeze
    end
  end

  RULES = {}.freeze
end
