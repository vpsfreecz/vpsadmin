module VpsAdmin::API::Tasks
  class OomReport < Base
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

      TransactionChains::Mail::OomReports.fire(vpses.values)
    end
  end
end
