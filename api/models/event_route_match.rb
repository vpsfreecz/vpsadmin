# frozen_string_literal: true

class EventRouteMatch < ApplicationRecord
  belongs_to :event
  belongs_to :event_route
  belongs_to :route_owner, class_name: 'User'

  validates :subject_relation,
            inclusion: { in: ->(_match) { ::EventRoutingContext.subject_relation_labels.keys } }
  validates :source,
            inclusion: { in: ->(_match) { ::EventRoutingContext.source_labels.keys } }
  validates :match_order, numericality: { only_integer: true }

  def event_route_label
    event_route&.display_label
  end

  def route_owner_login
    route_owner&.login
  end
end
