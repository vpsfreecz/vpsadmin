module VpsAdmin::API::Tasks
  class IncidentReport < Base
    # Process incident reports added by nodectl
    def process
      incidents = ::IncidentReport.where(reported_at: nil).to_a
      return if incidents.empty?

      if incidents.detect(&:cpu_limit)
        # If there are CPU limits in play, it is best to process the reports
        # one by one, so that one locked VPS would not prevent other reports
        # to be processes. This is because CPU limit changing use Vps::Update
        # chain.
        incidents.each do |inc|
          TransactionChains::IncidentReport::Process.fire([inc])
        rescue ResourceLocked
          warn "Unable to process incident ##{inc.id}: VPS #{inc.vps.id} is locked"
          next
        end
      else
        TransactionChains::IncidentReport::Process.fire(incidents)
      end
    end
  end
end
