module TransactionChains
  class EventDelivery::Email < ::TransactionChain
    label 'Event e-mail delivery'
    allow_empty

    def link_chain(delivery)
      return unless delivery.email_action?

      delivery.association(:event).target ||= delivery.event

      if delivery.prepared_state? && delivery.mail_log_id.blank?
        VpsAdmin::API::Notifications.render_email_delivery!(delivery)
        delivery.reload
      end

      return unless delivery.prepared_state?

      release_event_deliveries!(delivery.event)
    end
  end
end
