require_relative 'vps_evidence/rtnl_latency'

# Trusted startup defaults for the fixed evidence signals. This library loads
# before models and never registers handlers or changes the source predicate.
class VpsEvidence
  MAX_WINDOW = 7 * 86_400
  NUMERIC_SETTINGS = %i[window_seconds threshold_seconds repeat_seconds freshness_seconds].freeze
  SIGNALS = { 'rtnl_latency' => VpsAdmin::API::Evidence::RtnlLatency }.freeze

  class InvalidEvent < ArgumentError; end

  class Configuration
    attr_reader :defaults

    def initialize
      @defaults = {}
    end

    def signal(name, **values)
      key = name.to_s
      VpsEvidence.definition(key)
      raise ArgumentError, 'Duplicate VPS evidence signal' if defaults.has_key?(key)
      raise ArgumentError, 'Unsupported VPS evidence defaults' unless (values.keys - NUMERIC_SETTINGS).empty?

      VpsEvidence.validate_config!(VpsEvidence.definition(key)::DEFAULTS.merge(values))
      defaults[key] = values.freeze
    end
  end

  def self.definition(signal)
    SIGNALS.fetch(signal) { raise InvalidEvent, 'Unsupported VPS evidence signal' }
  end

  def self.categories
    SIGNALS.values.map { |handler| handler::CATEGORY }
  end

  def self.configure(&)
    raise ArgumentError, 'VPS evidence defaults are already initialized' if @configured || @finalized

    declaration = Configuration.new
    declaration.instance_eval(&)
    @site_defaults = declaration.defaults.freeze
    @configured = true
  end

  def self.finalize!
    path = File.join(VpsAdmin::API.root, 'config', 'vps_evidence.rb')
    raise ArgumentError, 'VPS evidence file did not configure defaults' if File.exist?(path) && !@configured

    @site_defaults ||= {}.freeze
    @finalized = true
  end

  def self.config(signal, values = nil)
    handler = definition(signal)
    values ||= SysConfig.where(category: handler::CATEGORY).to_h { |row| [row.name.to_sym, row.value] }
    effective = handler::DEFAULTS.merge((@site_defaults || {}).fetch(signal.to_s, {})).merge(values.symbolize_keys.compact)
    validate_config!(effective)
    effective.slice(*handler::DEFAULTS.keys)
  end

  def self.validate_config!(values)
    unless [true, false].include?(values[:enabled]) &&
           values[:window_seconds].is_a?(Integer) && values[:window_seconds].between?(60, MAX_WINDOW) &&
           values[:threshold_seconds].is_a?(Integer) && values[:threshold_seconds].between?(1, values[:window_seconds]) &&
           values[:repeat_seconds].is_a?(Integer) && values[:repeat_seconds].between?(60, MAX_WINDOW) &&
           values[:freshness_seconds].is_a?(Integer) && values[:freshness_seconds].between?(5, 300)
      raise ArgumentError, 'Invalid VPS evidence configuration'
    end
  end
end
