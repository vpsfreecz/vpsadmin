class VpsMaintenanceWindow < ActiveRecord::Base
  belongs_to :vps

  validate :check_window
  validate :check_length

  def check_window
    if is_open
      errors.add(:opens_at, 'must be present') unless opens_at
      errors.add(:closes_at, 'must be present') unless closes_at

    else
      errors.add(:opens_at, 'must not be present') if opens_at
      errors.add(:closes_at, 'must not be present') if closes_at
    end

    return if opens_at.nil? || closes_at.nil?

    if opens_at < 0
      errors.add(:opens_at, 'must be greater or equal to zero')

    elsif opens_at >= 24 * 60
      errors.add(:opens_at, 'must be less or equal to 23:59')
    end

    errors.add(:closes_at, 'must be greater than opens_at') if opens_at > closes_at

    return unless closes_at > 24 * 60

    errors.add(:closes_at, 'must be less or equal to 24:00')
  end

  def check_length
    if opens_at && closes_at && is_open && closes_at - opens_at < 60
      errors.add(:closes_at, 'must be at least 60 minutes after opens_at')
    end

    sum = vps.vps_maintenance_windows.where.not(id:).sum('closes_at - opens_at')
    sum += closes_at - opens_at if opens_at && closes_at && is_open

    return unless sum / 60.0 < 12

    errors.add(:closes_at, 'maintenance window per week must be at least 12 hours long')
  end

  # Generate maintenance windows specific for this migration
  #
  # @param vps [::Vps]
  # @param finish_weekday [Integer]
  # @param finish_minutes [Integer]
  # @return [Array<VpsMaintenanceWindow>] a list of temporary maintenance windows
  def self.make_for(vps, finish_weekday:, finish_minutes:)
    # The first open day is finish_weekday. Days after finish_weekday are
    # completely open as well. Days until finish_weekday remain closed.
    windows = (0..6).map do |i|
      ::VpsMaintenanceWindow.new(
        vps:,
        weekday: i
      )
    end

    finish_day = windows[finish_weekday]
    finish_day.assign_attributes(
      is_open: true,
      opens_at: finish_minutes,
      closes_at: 24 * 60
    )

    cur_day = Time.now.wday

    if cur_day == finish_day.weekday
      # The window is today, therefore all days are open
      windows.each do |w|
        next if w.weekday == finish_day.weekday

        w.assign_attributes(
          is_open: true,
          opens_at: 0,
          closes_at: 24 * 60
        )
      end

    else
      7.times do |day|
        next if day == finish_day.weekday

        is_open =
          if cur_day < finish_day.weekday
            # The window opens later this week:
            #  - the days before cur_day (next week) are open
            #  - the days after finish_day this week are open
            day < cur_day || day >= finish_day.weekday
          else
            # The window opens next week
            #  - the days next week after finish_day but before cur_day are open
            day >= finish_day.weekday && day < cur_day
          end

        if is_open
          windows[day].assign_attributes(
            is_open: true,
            opens_at: 0,
            closes_at: 24 * 60
          )
        else
          windows[day].assign_attributes(
            is_open: false,
            opens_at: nil,
            closes_at: nil
          )
        end
      end
    end

    windows.delete_if { |w| !w.is_open }

    raise 'programming error: no maintenance window is open' unless windows.detect { |w| w.is_open }

    windows
  end
end
