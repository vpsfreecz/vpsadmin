class EventRouteMatcher < ApplicationRecord
  CORE_FIELDS = %w[
    event_type
    category
    severity
    subject
    summary
    source_class
    source_id
    vps_id
    vps_hostname
    ip_addr
  ].freeze

  FIELD_LABELS = {
    'event_type' => 'Event type',
    'category' => 'Category',
    'severity' => 'Severity',
    'subject' => 'Subject',
    'summary' => 'Summary',
    'source_class' => 'Source type',
    'source_id' => 'Source ID',
    'vps_id' => 'VPS ID',
    'vps_hostname' => 'VPS hostname',
    'ip_addr' => 'IP address'
  }.freeze

  OPERATOR_LABELS = {
    '==' => '==',
    '!=' => '!=',
    '=~' => '=~',
    '!~' => '!~',
    '=*' => '=*',
    '!*' => '!*',
    '>' => '>',
    '>=' => '>=',
    '<' => '<',
    '<=' => '<='
  }.freeze

  OPERATORS = OPERATOR_LABELS.keys.freeze
  REGEXP_OPERATORS = %w[=~ !~].freeze
  GLOB_OPERATORS = %w[=* !*].freeze
  NUMERIC_OPERATORS = %w[> >= < <=].freeze
  GLOB_FLAGS = File::FNM_PATHNAME | File::FNM_EXTGLOB
  REGEXP_TIMEOUT = 0.05

  belongs_to :event_route

  validates :field, presence: true, length: { maximum: 100 }
  validates :operator, inclusion: { in: OPERATORS }
  validates :value, presence: true
  validate :check_field
  validate :check_regular_expression

  def self.field_labels(event_type: nil)
    labels = FIELD_LABELS.dup

    event_types =
      if event_type.present?
        [VpsAdmin::API::Events.type_for(event_type)].compact
      else
        VpsAdmin::API::Events.types
      end

    event_types.each do |type|
      type.parameters.each do |name, label|
        key = "parameters.#{name}"
        labels[key] ||= "#{type.label}: #{label}"
      end
    end

    labels
  end

  def self.operator_labels
    OPERATOR_LABELS
  end

  def matches?(event)
    actual = field_value(event)
    expected = value.to_s

    case operator
    when '=='
      actual.to_s == expected
    when '!='
      actual.to_s != expected
    when '=~'
      actual && actual.to_s.match?(regexp_value)
    when '!~'
      actual.nil? || !actual.to_s.match?(regexp_value)
    when '=*'
      actual && File.fnmatch?(expected, actual.to_s, GLOB_FLAGS)
    when '!*'
      actual.nil? || !File.fnmatch?(expected, actual.to_s, GLOB_FLAGS)
    when '>'
      numeric_value(actual) > numeric_value(expected)
    when '>='
      numeric_value(actual) >= numeric_value(expected)
    when '<'
      numeric_value(actual) < numeric_value(expected)
    when '<='
      numeric_value(actual) <= numeric_value(expected)
    else
      false
    end
  rescue ArgumentError, RegexpError
    false
  end

  def summary
    "#{field} #{operator} #{value}"
  end

  protected

  def check_field
    return if CORE_FIELDS.include?(field)
    return if VpsAdmin::API::Events.parameter_field?(field)

    errors.add(:field, 'is not a supported event field')
  end

  def check_regular_expression
    return unless REGEXP_OPERATORS.include?(operator)

    regexp_value
  rescue RegexpError => e
    errors.add(:value, "is not a valid regular expression: #{e.message}")
  end

  def regexp_value
    Regexp.new(value.to_s, timeout: REGEXP_TIMEOUT)
  end

  def field_value(event)
    case field
    when 'event_type'
      event.event_type
    when 'category'
      event.category
    when 'severity'
      event.severity
    when 'subject'
      event.subject
    when 'summary'
      event.summary
    when 'source_class'
      event.source_class
    when 'source_id'
      event.source_id
    when 'vps_id'
      event.vps_id
    when 'vps_hostname'
      event.vps&.hostname
    when 'ip_addr'
      event.ip_addr
    else
      parameter_value(event, field.delete_prefix('parameters.'))
    end
  end

  def parameter_value(event, name)
    name.split('.').reduce(event.parameters || {}) do |hash, key|
      break nil unless hash.is_a?(Hash)

      if hash.has_key?(key)
        hash[key]
      elsif hash.has_key?(key.to_sym)
        hash[key.to_sym]
      end
    end
  end

  def numeric_value(v)
    Float(v)
  end
end
