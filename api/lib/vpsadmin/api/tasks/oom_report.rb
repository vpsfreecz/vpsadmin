module VpsAdmin::API::Tasks
  class OomReport < Base
    DEFAULT_DAYS = 90

    # Remove old OOM reports
    # Accepts the following environment variables:
    # [DAYS] Delete OOM reports older than number of DAYS
    def prune
      total = 0

      # Delete in a loop with limited queries in case there's a lot of reports
      # to delete.
      loop do
        any = false

        ::OomReport.where('created_at < ?', days.day.ago).limit(10_000).each do |report|
          report.destroy!
          any = true
          total += 1
        end

        break unless any
      end

      puts "Deleted #{total} OOM reports"
    end

    protected

    def days
      ENV.fetch('DAYS', DEFAULT_DAYS).to_i
    end
  end
end
