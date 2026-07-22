# frozen_string_literal: true

class EventRouteMatch < ApplicationRecord
  TIME_INTERVAL_STATES = %w[active inactive muted].freeze

  belongs_to :event
  belongs_to :event_route
  belongs_to :route_owner, class_name: 'User'

  validates :subject_relation,
            inclusion: { in: ->(_match) { ::EventRoutingContext.subject_relation_labels.keys } }
  validates :source,
            inclusion: { in: ->(_match) { ::EventRoutingContext.source_labels.keys } }
  validates :match_order, numericality: { only_integer: true }
  validates :time_interval_state, inclusion: { in: TIME_INTERVAL_STATES }

  serialize :time_interval_snapshot, coder: JSON

  def event_route_label
    event_route&.display_label
  end

  def route_owner_login
    route_owner&.login
  end
end
