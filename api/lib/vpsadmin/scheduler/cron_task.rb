module VpsAdmin
  class Scheduler::CronTask
    class InvalidField < ArgumentError; end

    attr_reader :id, :class_name, :row_id, :minute, :hour, :day, :month, :weekday

    def initialize(id:, class_name:, row_id:, minute: '*', hour: '*', day: '*', month: '*', weekday: '*')
      @id = id
      @class_name = class_name
      @row_id = row_id
      @minute = parse_field(minute, 0, 59)
      @hour = parse_field(hour, 0, 23)
      @day = parse_field(day, 1, 31)
      @month = parse_field(month, 1, 12)
      @weekday = parse_field(weekday, 0, 6)
    end

    def matches?(time)
      minute_match?(time) \
        && hour_match?(time) \
        && day_match?(time) \
        && month_match?(time) \
        && weekday_match?(time)
    end

    def export
      {
        id:,
        class_name:,
        row_id:,
        minute:,
        hour:,
        day:,
        month:,
        weekday:
      }
    end

    private

    def parse_field(field, min, max)
      value = field.to_s
      return (min..max).to_a if value == '*'

      if value.match?(/\A[0-9]+\z/)
        number = value.to_i
        return [number] if number.between?(min, max)
      elsif (match = %r{\A(?:\*|([0-9]+)-([0-9]+))/([0-9]+)\z}.match(value))
        first = match[1] ? match[1].to_i : min
        last = match[2] ? match[2].to_i : max
        step = match[3].to_i

        if first.between?(min, max) && last.between?(first, max) && step.between?(1, max - min + 1)
          return (first..last).step(step).to_a
        end
      end

      raise InvalidField, "invalid cron field #{value.inspect} for #{min}..#{max}"
    end

    def minute_match?(time) = @minute.include?(time.min)
    def hour_match?(time) = @hour.include?(time.hour)
    def day_match?(time) = @day.include?(time.day)
    def month_match?(time) = @month.include?(time.month)
    def weekday_match?(time) = @weekday.include?(time.wday)
  end
end
