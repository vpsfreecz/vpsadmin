module VpsAdmin::API::Tasks
  class OomReport < Base
    DEFAULT_COOLDOWN = 3 * 60 * 60

    DEFAULT_DAYS = 90

    # Notify users about stale and previously unreported OOM reports
    #
    # Accepts the following environment variables:
    # [COOLDOWN]: Number of seconds from the last report to wait before notifying
    #             the user again
    def notify
      vpses = ::Vps.joins(:oom_reports).where(
        oom_reports: { reported_at: nil, ignored: false }
      ).group('vpses.id')
      return unless vpses.exists?

      TransactionChains::Vps::OomReports.fire2(
        args: [vpses],
        kwargs: { cooldown: cooldown }
      )
    end

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

    def cooldown
      ENV.fetch('COOLDOWN', DEFAULT_COOLDOWN).to_i
    end

    def days
      ENV.fetch('DAYS', DEFAULT_DAYS).to_i
    end
  end
end
