class VpsOutageWindow < ActiveRecord::Base
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

    elsif opens_at >= 24*60
      errors.add(:opens_at, 'must be less or equal to 23:59')
    end

    if opens_at > closes_at
      errors.add(:closes_at, 'must be greater than opens_at')
    end

    if closes_at > 24*60
      errors.add(:closes_at, 'must be less or equal to 24:00')
    end
  end

  def check_length
    if opens_at && closes_at && is_open && closes_at - opens_at < 60
      errors.add(:closes_at, 'must be at least 60 minutes after opens_at')
    end

    sum = vps.vps_outage_windows.where.not(id: self.id).sum('closes_at - opens_at')
    sum += closes_at - opens_at if opens_at && closes_at && is_open

    if sum / 60.0 < 12
      errors.add(:closes_at, 'outage window per week must be at least 12 hours long')
    end
  end
end
