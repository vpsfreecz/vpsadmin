class Event < ApplicationRecord
  MAX_SUMMARY_LENGTH = 16_384
  MAX_PARAMETERS_JSON_SIZE = 65_536
  MAX_PARAMETERS_DEPTH = 8
  MAX_PARAMETERS_MEMBERS = 100
  MAX_PARAMETER_KEY_LENGTH = 100

  SEVERITY_LABELS = {
    'info' => 'info',
    'warning' => 'warning',
    'error' => 'error',
    'critical' => 'critical'
  }.freeze

  ROUTING_STATE_LABELS = {
    'pending' => 'pending',
    'routed' => 'routed',
    'suppressed' => 'suppressed',
    'failed' => 'failed',
    'aborted' => 'aborted'
  }.freeze

  belongs_to :user, optional: true
  belongs_to :vps, optional: true
  has_many :event_deliveries, dependent: :delete_all
  has_many :event_routing_contexts, dependent: :delete_all
  has_many :event_route_matches, -> { order(:match_order, :id) }, dependent: :delete_all
  has_many :matched_event_routes, through: :event_route_matches, source: :event_route

  attr_accessor :runtime_event_context

  def runtime_email_context?
    runtime_event_context.present?
  end

  enum :severity, %i[info warning error critical], suffix: true
  enum :routing_state, %i[pending routed suppressed failed aborted], suffix: true

  serialize :parameters, coder: JSON

  before_validation :set_defaults

  validates :event_type, :category, :severity, :subject, :routing_state, presence: true
  validates :event_type, :category, length: { maximum: 100 }
  validates :subject, length: { maximum: 255 }
  validates :summary, length: { maximum: MAX_SUMMARY_LENGTH }, allow_nil: true
  validates :source_class, length: { maximum: 100 }, allow_nil: true
  validates :ip_addr, length: { maximum: 46 }, allow_nil: true
  validate :check_vps_owner
  validate :check_parameters

  def self.severity_labels
    SEVERITY_LABELS
  end

  def self.routing_state_labels
    ROUTING_STATE_LABELS
  end

  def self.visible_to(user)
    return all if user&.role == :admin
    return none unless user

    where(user_id: user.id)
  end

  def visible_to?(user)
    return false unless user
    return true if user.role == :admin

    user_id == user.id
  end

  def subject_relation
    viewer = ::User.current
    return unless viewer
    return 'system' if user_id.blank?
    return 'self' if user_id == viewer.id

    'other_user' if visible_to?(viewer)
  end

  def source
    return if source_class.blank? || source_id.blank?

    source_class.safe_constantize&.find_by(id: source_id)
  end

  def parameters_json
    JSON.dump(parameters || {})
  end

  protected

  def check_vps_owner
    return if user_id.blank? || vps.blank? || vps.user_id == user_id

    errors.add(:vps, 'does not belong to event user')
  end

  def check_parameters
    unless parameters.is_a?(Hash)
      errors.add(:parameters, 'must be a JSON object')
      return
    end

    if JSON.dump(parameters).bytesize > MAX_PARAMETERS_JSON_SIZE
      errors.add(:parameters, 'are too large')
      return
    end

    check_parameter_value(parameters, 0)
  rescue JSON::GeneratorError, TypeError
    errors.add(:parameters, 'must contain JSON-compatible values')
  end

  def check_parameter_value(value, depth)
    if depth > MAX_PARAMETERS_DEPTH
      errors.add(:parameters, 'are too deeply nested')
      return
    end

    case value
    when Hash
      check_parameter_hash(value, depth)
    when Array
      check_parameter_array(value, depth)
    when String, Numeric, TrueClass, FalseClass, NilClass
      nil
    else
      errors.add(:parameters, 'must contain JSON-compatible values')
    end
  end

  def check_parameter_hash(hash, depth)
    if hash.size > MAX_PARAMETERS_MEMBERS
      errors.add(:parameters, 'contain too many keys')
      return
    end

    hash.each do |key, value|
      unless key.is_a?(String) || key.is_a?(Symbol)
        errors.add(:parameters, 'keys must be strings')
        next
      end

      if key.to_s.length > MAX_PARAMETER_KEY_LENGTH
        errors.add(:parameters, 'keys are too long')
        next
      end

      check_parameter_value(value, depth + 1)
    end
  end

  def check_parameter_array(array, depth)
    if array.size > MAX_PARAMETERS_MEMBERS
      errors.add(:parameters, 'contain too many array items')
      return
    end

    array.each do |value|
      check_parameter_value(value, depth + 1)
    end
  end

  def set_defaults
    type = VpsAdmin::API::Events.type_for(event_type) if event_type.present?

    self.category ||= type&.category || 'general'
    self.severity ||= type&.severity || 'info'
    self.subject ||= type&.label || event_type
    self.routing_state ||= 'pending'
    self.parameters ||= {}
  end
end
