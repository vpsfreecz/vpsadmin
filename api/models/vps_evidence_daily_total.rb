require 'time'

class VpsEvidenceDailyTotal < ApplicationRecord
  belongs_to :vps
  belongs_to :user
  attr_readonly :day, :vps_id, :signal, :user_id, :accounting_since, :accounting_epoch_key

  def self.epoch_key(value)
    value ? value.utc.iso8601(6) : '-'
  end

  # Called only for new disjoint ledger pieces, under the same VPS lock and
  # acceptance transaction. Occurrence days never come from receipt timestamps.
  def self.record_piece!(vps:, signal:, from_at:, to_at:, accepted_at:)
    cursor = from_at.utc
    while cursor < to_at
      day = cursor.to_date
      boundary = Time.utc(day.year, day.month, day.day) + 86_400
      last = [to_at, boundary].min
      credit = ((last.to_r - cursor.to_r) * 1_000_000).to_i
      if credit > 0
        row = lock.find_or_initialize_by(vps_id: vps.id, signal:, user_id: vps.user_id,
                                         accounting_epoch_key: epoch_key(vps.incident_accounting_since), day:)
        row.accounting_since = vps.incident_accounting_since if row.new_record?
        row.recorded_us = (row.recorded_us || 0) + credit
        row.first_accepted_at = [row.first_accepted_at, accepted_at].compact.min
        row.last_accepted_at = [row.last_accepted_at, accepted_at].compact.max
        row.save!
      end
      cursor = last
    end
  end

  def self.prune!(now: Time.now.utc)
    where('day < ?', now.utc.to_date - 31).delete_all
  end
end
