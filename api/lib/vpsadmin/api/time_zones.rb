# frozen_string_literal: true

require 'active_support/time'
require 'time'
require 'tzinfo'

module VpsAdmin::API::TimeZones
  DEFAULT_TIME_FORMAT = '%Y-%m-%d %H:%M %Z'
  DEFAULT_DATE_FORMAT = '%Y-%m-%d'

  module_function

  def identifiers
    @identifiers ||= TZInfo::Timezone.all_identifiers.sort.freeze
  end

  def valid?(time_zone)
    return true if time_zone.nil? || time_zone.empty?

    identifiers.include?(time_zone)
  end

  def format_time(value, time_zone: nil, format: DEFAULT_TIME_FORMAT)
    time = coerce_time(value)
    local_time(time, time_zone).strftime(format)
  end

  def format_date(value, time_zone: nil, format: DEFAULT_DATE_FORMAT)
    if value.respond_to?(:to_time)
      format_time(value, time_zone:, format:)
    else
      value.strftime(format)
    end
  end

  def local_time(time, time_zone)
    return time.localtime if time_zone.nil? || time_zone.empty?

    ActiveSupport::TimeZone[time_zone].at(time.to_f)
  end

  def coerce_time(value)
    return value if value.respond_to?(:to_f)

    Time.parse(value.to_s)
  end
end
