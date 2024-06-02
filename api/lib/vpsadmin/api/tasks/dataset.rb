module VpsAdmin::API::Tasks
  class Dataset < Base
    DAYS = ENV['DAYS'] ? ENV['DAYS'].to_i : 365

    # Prune dataset property log
    # Accepts the following environment variables:
    # [DAYS] Delete dataset property logs older than number of DAYS
    def prune_property_logs
      cnt = ::DatasetPropertyHistory.where('created_at < ?', DAYS.day.ago).delete_all
      puts "Deleted #{cnt} dataset property logs"
    end
  end
end
