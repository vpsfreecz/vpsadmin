module VpsAdmin::API::Plugins::Monitoring::TransactionChains
  class Alert < ::TransactionChain
    label 'Alert'
    allow_empty

    def link_chain(event)
      concerns(:affect, [event.object.class.name, event.object.id])
      event.call_action(self, event)
      event.increment!(:alert_count) unless empty?
    end
  end
end
