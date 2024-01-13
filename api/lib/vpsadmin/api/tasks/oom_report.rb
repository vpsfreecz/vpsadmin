module VpsAdmin::API::Tasks
  class OomReport < Base
    COOLDOWN = ENV['COOLDOWN'] ? ENV['COOLDOWN'].to_i : 3*60*60

    # Notify users about stale and previously unreported OOM reports
    #
    # Accepts the following environment variables:
    # [COOLDOWN]: Number of seconds from the last report to wait before notifying
    #             the user again
    def notify
      vpses = ::Vps.joins(:oom_reports).where(
        oom_reports: {reported_at: nil},
      ).group('vpses.id')

      TransactionChains::Vps::OomReports.fire2(
        args: [vpses],
        kwargs: {cooldown: COOLDOWN},
      )
    end
  end
end
