class EventRouteMatcher < ApplicationRecord
  COMMON_FIELDS = {
    'event_type' => {
      description: 'Unique event type name',
      type: 'string',
      example: 'vps.oom_report'
    },
    'default_routed' => {
      description: 'Whether the event is delivered by the default route',
      type: 'boolean',
      example: true
    },
    'category' => {
      description: 'Event category used for grouping',
      type: 'string',
      example: 'vps'
    },
    'severity' => {
      description: 'Event severity',
      type: 'string',
      example: 'warning',
      choices: -> { ::Event.severity_labels.keys }
    },
    'subject' => {
      description: 'Short event subject',
      type: 'string',
      example: 'OOM report for VPS #123'
    },
    'summary' => {
      description: 'Longer event summary',
      type: 'string',
      example: 'vpsAdmin recorded 3 out-of-memory events'
    },
    'roles' => {
      description: 'Notification roles declared by the event type',
      type: 'string_list',
      example: %w[account],
      choices: %w[account admin]
    },
    'subject_relation' => {
      description: 'Relationship between route owner and event subject',
      type: 'string',
      example: 'self',
      choices: -> { ::EventRoutingContext.subject_relation_labels.keys }
    },
    'subject_user_id' => {
      description: 'User ID of the event subject',
      type: 'integer',
      example: 123
    },
    'subject_is_self' => {
      description: 'Whether the event subject is the route owner',
      type: 'boolean',
      example: true
    },
    'subject_is_admin_visible' => {
      description: 'Whether an admin route sees another user subject',
      type: 'boolean',
      example: false
    }
  }.freeze

  OPERATOR_LABELS = {
    '==' => '==',
    '!=' => '!=',
    '=~' => '=~',
    '!~' => '!~',
    '=*' => '=*',
    '!*' => '!*',
    'contains' => 'contains',
    'not_contains' => 'does not contain',
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
  validate :check_operator_for_field
  validate :check_regular_expression

  def self.field_labels(event_type: nil)
    field_metadata(event_type:).to_h { |field| [field.fetch(:name), field.fetch(:description)] }
  end

  def self.field_types(event_type: nil)
    field_metadata(event_type:).to_h { |field| [field.fetch(:name), field.fetch(:type)] }
  end

  def self.field_metadata(event_type: nil)
    fields = COMMON_FIELDS.map do |name, config|
      field_metadata_hash(name, config)
    end

    event_types =
      if event_type.present? && event_type != '__any__'
        [VpsAdmin::API::Events.type_for(event_type)].compact
      else
        VpsAdmin::API::Events.types
      end

    event_types.each do |type|
      type.fields.each do |field|
        next if fields.any? { |existing| existing.fetch(:name) == field.fetch(:name) }

        fields << field
      end
    end

    fields
  end

  def self.field_metadata_hash(name, config)
    type = config.fetch(:type)
    choices = config[:choices]
    choices = choices.call if choices.respond_to?(:call)
    {
      name:,
      description: config.fetch(:description),
      type:,
      example: config.fetch(:example),
      operators: VpsAdmin::API::Events::FIELD_TYPE_OPERATORS.fetch(type)
    }.tap do |ret|
      ret[:choices] = choices if choices
    end
  end

  def self.field_map(event_type: nil)
    field_metadata(event_type:).to_h { |field| [field.fetch(:name), field] }
  end

  def self.field?(field)
    field_map.has_key?(field.to_s)
  end

  def self.field_value(event, field, route_context: nil)
    field = field.to_s
    case field
    when 'event_type'
      event.event_type
    when 'default_routed'
      VpsAdmin::API::Events.default_routed?(event.event_type)
    when 'category'
      event.category
    when 'severity'
      event.severity
    when 'subject'
      event.subject
    when 'summary'
      event.summary
    when 'subject_relation', 'subject_user_id',
         'subject_is_self', 'subject_is_admin_visible'
      context_field_value(field, route_context)
    else
      event_payload_value(event, field)
    end
  end

  def self.operator_labels
    OPERATOR_LABELS
  end

  def field_type
    field_metadata&.fetch(:type, nil)
  end

  def matches?(event, route_context: nil)
    actual = field_value(event, route_context:)
    return false if actual.nil?

    case operator
    when '=='
      comparable_value(actual) == comparable_value(value)
    when '!='
      comparable_value(actual) != comparable_value(value)
    when '=~'
      actual.to_s.match?(regexp_value)
    when '!~'
      !actual.to_s.match?(regexp_value)
    when '=*'
      File.fnmatch?(value.to_s, actual.to_s, GLOB_FLAGS)
    when '!*'
      !File.fnmatch?(value.to_s, actual.to_s, GLOB_FLAGS)
    when 'contains'
      contains_value?(actual, value)
    when 'not_contains'
      !contains_value?(actual, value)
    when '>'
      comparable_value(actual) > comparable_value(value)
    when '>='
      comparable_value(actual) >= comparable_value(value)
    when '<'
      comparable_value(actual) < comparable_value(value)
    when '<='
      comparable_value(actual) <= comparable_value(value)
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
    return if self.class.field?(field)

    errors.add(:field, 'is not a supported event field')
  end

  def check_operator_for_field
    return if field_type.nil?
    return if VpsAdmin::API::Events::FIELD_TYPE_OPERATORS.fetch(field_type).include?(operator)

    errors.add(:operator, "is not supported for #{field_type} fields")
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

  def field_value(event, route_context:)
    self.class.field_value(event, field, route_context:)
  end

  class << self
    protected

    def event_payload_value(event, field)
      field = field.to_s
      definition = VpsAdmin::API::Events.type_for(event.event_type)&.definition
      return definition.payload_value(event, field) if definition&.field_for(field)
      return unless COMMON_FIELDS.has_key?(field)

      payload = event.payload || {}
      field_sym = field.to_sym
      if payload.has_key?(field)
        payload[field]
      elsif payload.has_key?(field_sym)
        payload[field_sym]
      end
    end

    def context_field_value(field, route_context)
      return unless route_context

      case field
      when 'subject_relation'
        route_context.subject_relation
      when 'subject_user_id'
        route_context.subject_user_id
      when 'subject_is_self'
        route_context.subject_is_self
      when 'subject_is_admin_visible'
        route_context.subject_is_admin_visible
      end
    end
  end

  def contains_value?(actual, expected)
    return false unless actual.is_a?(Array)

    actual.map { |item| comparable_list_value(item) }.include?(comparable_list_value(expected))
  end

  def comparable_value(v)
    case field_type
    when 'integer'
      Integer(v)
    when 'number'
      Float(v)
    when 'datetime'
      VpsAdmin::API::Events.parse_time(v) || raise(ArgumentError, 'invalid datetime')
    when 'boolean'
      normalize_boolean_value(v)
    else
      v.to_s
    end
  end

  def comparable_list_value(v)
    field_type == 'integer_list' ? Integer(v) : v.to_s
  end

  def field_metadata
    self.class.field_map.fetch(field, nil)
  end

  def boolean_field?
    field_type == 'boolean'
  end

  def normalize_boolean_value(v)
    case v
    when true
      'true'
    when false
      'false'
    else
      case v.to_s.strip.downcase
      when '1', 'true', 'yes', 'y', 'on'
        'true'
      when '0', 'false', 'no', 'n', 'off'
        'false'
      else
        v.to_s
      end
    end
  end
end
