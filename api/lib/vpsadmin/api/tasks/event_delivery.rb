module VpsAdmin::API::Tasks
  class EventDelivery < Base
    def deliver_emails
      VpsAdmin::API::Notifications::Dispatcher.dispatch_due('email', limit:)
    end

    def deliver_webhooks
      VpsAdmin::API::Notifications::Dispatcher.dispatch_due('webhook', limit:)
    end

    def deliver_telegrams
      VpsAdmin::API::Notifications::Dispatcher.dispatch_due('telegram', limit:)
    end

    protected

    def limit
      ENV.fetch('LIMIT', VpsAdmin::API::Notifications::DEFAULT_LIMIT).to_i
    end
  end
end
