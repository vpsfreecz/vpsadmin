# frozen_string_literal: true

class EventTimeInterval < ApplicationRecord
  MAX_INTERVALS_PER_USER = 50
  MAX_SPECS = 20
  MAX_RANGES_PER_DIMENSION = 20
  MAX_SPECS_JSON_SIZE = 65_536
  DIMENSIONS = %w[times weekdays days_of_month months years].freeze
  WEEKDAYS = %w[sunday monday tuesday wednesday thursday friday saturday].freeze
  TIME_PATTERN = /\A(?:[01]\d|2[0-3]):[0-5]\d\z/
  END_TIME_PATTERN = /\A(?:(?:[01]\d|2[0-3]):[0-5]\d|24:00)\z/

  belongs_to :user
  has_many :event_route_time_intervals, dependent: :restrict_with_error
  has_many :event_routes, through: :event_route_time_intervals

  serialize :specs, coder: JSON

  before_validation :set_default_time_zone
  validate :normalize_and_check_specs

  validates :name,
            presence: true,
            length: { maximum: 255 },
            uniqueness: { scope: :user_id }
  validates :time_zone, presence: true, length: { maximum: 255 }
  validate :check_time_zone
  validate :check_interval_limit, on: :create

  def self.create_for_user!(user:, **attributes)
    transaction do
      user.lock!
      create!(user:, **attributes)
    end
  end

  def destroy_if_unassigned!
    with_lock { destroy! }
  end

  def matches?(time)
    local_time = VpsAdmin::API::TimeZones.local_time(time, time_zone)
    specs.any? { |spec| spec_matches?(spec, local_time) }
  end

  def matches_now
    matches?(Time.now)
  end

  def display_summary
    count = specs&.length.to_i
    "#{count} #{count == 1 ? 'specification' : 'specifications'} in #{time_zone}"
  end

  def route_reference_count
    event_route_time_intervals.count
  end

  def active_route_reference_count
    event_route_time_intervals.active_mode.count
  end

  def mute_route_reference_count
    event_route_time_intervals.mute_mode.count
  end

  protected

  def set_default_time_zone
    self.time_zone = user&.time_zone.presence || 'UTC' if time_zone.blank?
  end

  def check_time_zone
    return if time_zone.present? && VpsAdmin::API::TimeZones.valid?(time_zone)

    errors.add(:time_zone, 'is not a valid time zone')
  end

  def check_interval_limit
    return unless user
    return if user.event_time_intervals.where.not(id:).count < MAX_INTERVALS_PER_USER

    errors.add(:base, "cannot have more than #{MAX_INTERVALS_PER_USER} event time intervals")
  end

  def normalize_and_check_specs
    self.specs = self.class.normalize_specs(specs)
  rescue ArgumentError => e
    errors.add(:specs, e.message)
  end

  def spec_matches?(spec, local_time)
    time_ranges_match?(spec.fetch('times'), local_time) &&
      integer_ranges_match?(spec.fetch('weekdays'), local_time.wday) &&
      day_of_month_ranges_match?(spec.fetch('days_of_month'), local_time) &&
      integer_ranges_match?(spec.fetch('months'), local_time.month) &&
      integer_ranges_match?(spec.fetch('years'), local_time.year)
  end

  def time_ranges_match?(ranges, local_time)
    return true if ranges.empty?

    seconds = (local_time.hour * 3600) + (local_time.min * 60) + local_time.sec
    ranges.any? do |range|
      start_seconds = self.class.time_to_seconds(range.fetch('start_time'))
      end_seconds = self.class.time_to_seconds(range.fetch('end_time'))
      seconds >= start_seconds && seconds < end_seconds
    end
  end

  def integer_ranges_match?(ranges, actual)
    ranges.empty? || ranges.any? do |range|
      actual.between?(range.fetch('start'), range.fetch('end'))
    end
  end

  def day_of_month_ranges_match?(ranges, local_time)
    return true if ranges.empty?

    last_day = Time.days_in_month(local_time.month, local_time.year)
    ranges.any? do |range|
      first = resolve_day_of_month(range.fetch('start'), last_day)
      last = resolve_day_of_month(range.fetch('end'), last_day)
      local_time.day.between?(first, last)
    end
  end

  def resolve_day_of_month(value, last_day)
    if value > 0
      [value, last_day].min
    else
      [last_day + value + 1, 1].max
    end
  end

  class << self
    def normalize_specs(value)
      raise ArgumentError, 'must be a list' unless value.is_a?(Array)
      raise ArgumentError, 'must contain at least one specification' if value.empty?
      raise ArgumentError, "cannot contain more than #{MAX_SPECS} specifications" if value.length > MAX_SPECS

      normalized = value.map.with_index do |spec, index|
        normalize_spec(spec, index)
      end

      if JSON.dump(normalized).bytesize > MAX_SPECS_JSON_SIZE
        raise ArgumentError, 'are too large'
      end

      normalized
    rescue JSON::GeneratorError, TypeError
      raise ArgumentError, 'must contain JSON-compatible values'
    end

    def time_to_seconds(value)
      return 86_400 if value == '24:00'

      hours, minutes = value.split(':').map(&:to_i)
      (hours * 3600) + (minutes * 60)
    end

    protected

    def normalize_spec(value, index)
      spec = stringify_hash(value, "specification #{index + 1}")
      unknown = spec.keys - DIMENSIONS
      raise ArgumentError, "specification #{index + 1} has unknown fields: #{unknown.join(', ')}" if unknown.any?

      ret = {
        'times' => normalize_times(spec.fetch('times', []), index),
        'weekdays' => normalize_weekdays(spec.fetch('weekdays', []), index),
        'days_of_month' => normalize_integer_ranges(
          spec.fetch('days_of_month', []),
          index,
          'days_of_month',
          allowed: (-31..31).to_a - [0],
          same_sign: true
        ),
        'months' => normalize_integer_ranges(
          spec.fetch('months', []),
          index,
          'months',
          allowed: 1..12
        ),
        'years' => normalize_integer_ranges(
          spec.fetch('years', []),
          index,
          'years',
          allowed: 1..9999
        )
      }

      if ret.values.all?(&:empty?)
        raise ArgumentError, "specification #{index + 1} must constrain at least one dimension"
      end

      ret
    end

    def normalize_times(value, spec_index)
      ranges = check_range_list(value, spec_index, 'times')
      ranges.map.with_index do |range, range_index|
        row = stringify_hash(range, range_label(spec_index, 'times', range_index))
        check_range_keys(row, spec_index, 'times', range_index, %w[start_time end_time])
        start_time = row.fetch('start_time').to_s
        end_time = row.fetch('end_time').to_s
        unless TIME_PATTERN.match?(start_time) && END_TIME_PATTERN.match?(end_time)
          raise ArgumentError, "#{range_label(spec_index, 'times', range_index)} must use HH:MM values"
        end
        unless time_to_seconds(start_time) < time_to_seconds(end_time)
          raise ArgumentError, "#{range_label(spec_index, 'times', range_index)} must end after it starts"
        end

        { 'start_time' => start_time, 'end_time' => end_time }
      end
    end

    def normalize_weekdays(value, spec_index)
      ranges = check_range_list(value, spec_index, 'weekdays')
      ranges.map.with_index do |range, range_index|
        row = stringify_hash(range, range_label(spec_index, 'weekdays', range_index))
        check_range_keys(row, spec_index, 'weekdays', range_index, %w[start end])
        first = weekday_number(row.fetch('start'), spec_index, range_index)
        last = weekday_number(row.fetch('end', row.fetch('start')), spec_index, range_index)
        if first > last
          raise ArgumentError, "#{range_label(spec_index, 'weekdays', range_index)} cannot wrap"
        end

        { 'start' => first, 'end' => last }
      end
    end

    def normalize_integer_ranges(value, spec_index, dimension, allowed:, same_sign: false)
      ranges = check_range_list(value, spec_index, dimension)
      ranges.map.with_index do |range, range_index|
        row = stringify_hash(range, range_label(spec_index, dimension, range_index))
        check_range_keys(row, spec_index, dimension, range_index, %w[start end])
        first = integer_value(row.fetch('start'), spec_index, dimension, range_index)
        last = integer_value(row.fetch('end', row.fetch('start')), spec_index, dimension, range_index)
        unless allowed.include?(first) && allowed.include?(last)
          raise ArgumentError, "#{range_label(spec_index, dimension, range_index)} is outside the supported range"
        end
        if first > last
          raise ArgumentError, "#{range_label(spec_index, dimension, range_index)} has a reversed range"
        end
        if same_sign && (first < 0) != (last < 0)
          raise ArgumentError, "#{range_label(spec_index, dimension, range_index)} cannot cross zero"
        end

        { 'start' => first, 'end' => last }
      end
    end

    def check_range_list(value, spec_index, dimension)
      unless value.is_a?(Array)
        raise ArgumentError, "specification #{spec_index + 1} #{dimension} must be a list"
      end

      if value.length > MAX_RANGES_PER_DIMENSION
        raise ArgumentError,
              "specification #{spec_index + 1} #{dimension} cannot contain more than " \
              "#{MAX_RANGES_PER_DIMENSION} ranges"
      end

      value
    end

    def stringify_hash(value, label)
      raise ArgumentError, "#{label} must be an object" unless value.is_a?(Hash)

      value.to_h { |key, item| [key.to_s, item] }
    end

    def check_range_keys(row, spec_index, dimension, range_index, allowed)
      unknown = row.keys - allowed
      return if unknown.empty?

      raise ArgumentError,
            "#{range_label(spec_index, dimension, range_index)} has unknown fields: #{unknown.join(', ')}"
    end

    def weekday_number(value, spec_index, range_index)
      number = WEEKDAYS.index(value.to_s.downcase)
      return number if number

      raise ArgumentError, "#{range_label(spec_index, 'weekdays', range_index)} has an invalid weekday"
    end

    def integer_value(value, spec_index, dimension, range_index)
      Integer(value)
    rescue ArgumentError, TypeError
      raise ArgumentError, "#{range_label(spec_index, dimension, range_index)} must use integers"
    end

    def range_label(spec_index, dimension, range_index)
      "specification #{spec_index + 1} #{dimension} range #{range_index + 1}"
    end
  end
end
