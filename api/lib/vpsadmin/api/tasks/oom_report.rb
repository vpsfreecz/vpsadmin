module VpsAdmin::API::Tasks
  class OomReport < Base
    COOLDOWN = ENV['COOLDOWN'] ? ENV['COOLDOWN'].to_i : 3*60*60

    # Process new OOM reports and inform users
    #
    # Accepts the following environment variables:
    # [COOLDOWN]: Number of seconds from the last report to wait before notifying
    #             the user again
    def process
      accepted = 0
      disregarded = 0
      vpses = {}

      ::OomReport.unscoped.where(processed: false).each do |r|
        if r.vps.nil?
          puts "Report #{r.id}: VPS #{r.vps_id} not found, disregarding"
          r.destroy!
          disregarded += 1
          next
        end

        puts "Report #{r.id}: accepted"
        r.update(processed: true)
        accepted += 1
        vpses[r.vps_id] = r.vps unless vpses.has_key?(r.vps_id)
      end

      puts "Accepted #{accepted} reports from #{vpses.length} VPS"
      puts "Disregarded #{disregarded} reports"

      TransactionChains::Mail::OomReports.fire2(
        args: [vpses.values],
        kwargs: {cooldown: COOLDOWN},
      )
    end

    # Notify users about stale and previously unreported OOM reports
    #
    # Accepts the following environment variables:
    # [COOLDOWN]: Number of seconds from the last report to wait before notifying
    #             the user again
    def notify
      vpses = ::Vps.joins(:oom_reports).where(
        oom_reports: {reported_at: nil},
      ).group('vpses.id')

      TransactionChains::Mail::OomReports.fire2(
        args: [vpses],
        kwargs: {cooldown: COOLDOWN},
      )
    end
  end
end
