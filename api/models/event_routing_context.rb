class EventRoutingContext < ApplicationRecord
  SUBJECT_RELATION_LABELS = {
    'self' => 'self',
    'other_user' => 'other user',
    'system' => 'system',
    'rbac' => 'RBAC'
  }.freeze

  SOURCE_LABELS = {
    'direct_route' => 'direct route',
    'visible_route' => 'visible route',
    'system_route' => 'system route',
    'migration' => 'migration',
    'rbac_route' => 'RBAC route'
  }.freeze

  ROUTING_STATE_LABELS = {
    'routed' => 'routed',
    'suppressed' => 'suppressed',
    'failed' => 'failed',
    'read' => 'read',
    'acknowledged' => 'acknowledged',
    'bookmarked' => 'bookmarked'
  }.freeze

  belongs_to :event
  belongs_to :recipient_user, class_name: 'User', foreign_key: :user_id
  belongs_to :matched_event_route, class_name: 'EventRoute', optional: true
  has_many :event_deliveries, dependent: :nullify

  enum :routing_state, %i[routed suppressed failed read acknowledged bookmarked], suffix: true

  validates :subject_relation, inclusion: { in: SUBJECT_RELATION_LABELS.keys }
  validates :source, inclusion: { in: SOURCE_LABELS.keys }
  validates :event_id, uniqueness: { scope: :user_id }

  def self.subject_relation_labels
    SUBJECT_RELATION_LABELS
  end

  def self.source_labels
    SOURCE_LABELS
  end

  def self.routing_state_labels
    ROUTING_STATE_LABELS
  end
end
