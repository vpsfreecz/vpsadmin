module VpsAdmin
  class Scheduler::CronTask
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

    private

    def parse_field(field, min, max)
      if field == '*'
        (min..max).to_a
      else
        Array(field.to_i)
      end
    end

    def minute_match?(time) = @minute.include?(time.min)
    def hour_match?(time) = @hour.include?(time.hour)
    def day_match?(time) = @day.include?(time.day)
    def month_match?(time) = @month.include?(time.month)
    def weekday_match?(time) = @weekday.include?(time.wday)
  end
end
