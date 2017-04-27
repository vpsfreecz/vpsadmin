module VpsAdmin::API::Plugins::Monitoring::TransactionChains
  class Alert < ::TransactionChain
    label 'Alert'
    allow_empty

    def link_chain(event)
      concerns(:affect, [event.object, event.object.id])
      event.call_action(self, event)
    end
  end
end
