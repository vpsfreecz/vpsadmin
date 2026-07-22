# frozen_string_literal: true

class EventRouteTimeInterval < ApplicationRecord
  belongs_to :event_route
  belongs_to :event_time_interval

  enum :mode, %i[active mute], suffix: true

  def self.mode_labels
    modes.keys.to_h { |mode| [mode, mode.capitalize] }
  end

  validates :mode, presence: true
  validates :event_time_interval_id, uniqueness: { scope: :event_route_id }
  validate :check_owner
  validate :check_route_limit, on: :create

  def self.assign!(event_route:, event_time_interval:, mode:)
    transaction do
      event_time_interval.lock!
      event_route.lock!
      create!(event_route:, event_time_interval:, mode:)
    end
  end

  protected

  def check_owner
    return unless event_route && event_time_interval
    return if event_route.user_id == event_time_interval.user_id

    errors.add(:event_time_interval, 'does not belong to the route owner')
  end

  def check_route_limit
    return unless event_route
    return if event_route.event_route_time_intervals.where.not(id:).count < EventRoute::MAX_TIME_INTERVALS

    errors.add(:base, "cannot assign more than #{EventRoute::MAX_TIME_INTERVALS} time intervals to a route")
  end
end
