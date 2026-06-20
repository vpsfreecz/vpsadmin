module VpsAdmin::API::Tasks
  class IncidentReport < Base
    # Process incident reports added by nodectl
    def process
      incidents = ::IncidentReport.where(reported_at: nil).to_a
      return if incidents.empty?

      TransactionChains::IncidentReport::Utils.fire_process(incidents) do |inc|
        warn "Unable to process incident ##{inc.id}: VPS #{inc.vps.id} is locked"
      end
    end
  end
end
