class DnsServerZoneTransferLog < ApplicationRecord
  belongs_to :dns_server_zone

  enum :status, %i[success failed]

  validates :dns_server_zone, :event_key, :event_at, :status, presence: true
  validates :event_key, uniqueness: true

  def self.prune!(days: 365, batch_size: 10_000)
    cnt = 0

    loop do
      ids = where('event_at < ?', days.day.ago).limit(batch_size).pluck(:id)
      break if ids.empty?

      ::DnsServerZone.where(last_transfer_log_id: ids).update_all(last_transfer_log_id: nil)
      cnt += where(id: ids).delete_all
    end

    cnt
  end
end
