module VpsAdmin::API::Tasks
  class Vps < Base
    DAYS = ENV['DAYS'] ? ENV['DAYS'].to_i : 365

    # Prune VPS status log
    # Accepts the following environment variables:
    # [DAYS] Delete VPS status logs older than number of DAYS
    def prune_status_logs
      cnt = ::VpsStatus.where('created_at < ?', DAYS.day.ago).delete_all
      puts "Deleted #{cnt} VPS status logs"
    end
  end
end
